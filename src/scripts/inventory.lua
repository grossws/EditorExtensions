local inventory = {}

local gui = require("__flib__.gui-beta")
local migration = require("__flib__.migration")
local reverse_defines = require("__flib__.reverse-defines")

-- -----------------------------------------------------------------------------
-- INVENTORY AND CURSOR STACK SYNC

function inventory.create_sync_inventories(player_table, player)
  -- determine prefix based on controller type
  local prefix = reverse_defines.controllers[player.controller_type].."_"
  -- hand location
  local hand_location = player.hand_location or {}
  -- iterate all inventories
  local sync_tables = {}
  for _, name in ipairs{"cursor", "main", "guns", "armor", "ammo"} do
    local sync_filters = {}
    local sync_inventory
    local inventory_def = defines.inventory[prefix..name]
    if name == "cursor" then
      sync_inventory = game.create_inventory(1)
      local cursor_stack = player.cursor_stack
      if cursor_stack and cursor_stack.valid_for_read then
        sync_inventory[1].transfer_stack(cursor_stack)
      end
    elseif inventory_def then
      local source_inventory = player.get_inventory(inventory_def)
      local get_filter = source_inventory.get_filter
      local supports_filters = source_inventory.supports_filters()
      local source_inventory_len = #source_inventory
      sync_inventory = game.create_inventory(source_inventory_len)
      for i = 1, source_inventory_len do
        sync_inventory[i].transfer_stack(source_inventory[i])
        if supports_filters then
          sync_filters[i] = get_filter(i)
        end
      end
    end
    if sync_inventory then
      sync_tables[name] = {
        filters = sync_filters,
        hand_location = (hand_location.inventory == inventory_def and hand_location.slot or nil),
        inventory = sync_inventory
      }
    end
  end
  player_table.sync_data = sync_tables
end

function inventory.get_from_sync_inventories(player_table, player)
  -- determine prefix based on controller type
  local prefix = reverse_defines.controllers[player.controller_type].."_"
  -- iterate all inventories
  local sync_data = player_table.sync_data
  for _, name in ipairs{"ammo", "armor", "cursor", "guns", "main"} do
    local sync_table = sync_data[name]
    -- god mode doesn't have every inventory
    if sync_table then
      local sync_filters = sync_table.filters
      local sync_inventory = sync_table.inventory
      if name == "cursor" and player.cursor_stack then
        player.cursor_stack.transfer_stack(sync_inventory[1])
      else
        local inventory_def = defines.inventory[prefix..name]
        if inventory_def then
          local destination_inventory = player.get_inventory(inventory_def)
          local set_filter = destination_inventory.set_filter
          for i = 1, math.min(#destination_inventory, #sync_inventory) do
            if sync_filters[i] then
              set_filter(i, sync_filters[i])
            end
            destination_inventory[i].transfer_stack(sync_inventory[i])
          end
          local hand_location = sync_table.hand_location
          if hand_location then
            player.hand_location = {inventory = inventory_def, slot = hand_location}
          end
        end
      end
      sync_inventory.destroy()
    end
  end
  player_table.sync_data = nil
end

-- -----------------------------------------------------------------------------
-- INFINITY INVENTORY FILTERS

local filters_table_version = 0
local filters_table_migrations = {}

function inventory.import_filters(player, string)
  local decoded_string = game.decode_string(string)
  if
    decoded_string
    and string.sub(decoded_string, 1, 16) == "EditorExtensions"
    and string.sub(decoded_string, 18, 34) == "inventory_filters"
  then
    -- extract version for migrations
    local _, _, version, json = string.find(decoded_string, "^.-%-.-%-(%d-)%-(.*)$")
    local input = game.json_to_table(json)
    -- run migrations
    migration.run(version, filters_table_migrations, nil, input)
    -- sanitize the filters to only include currently existing prototypes
    local item_prototypes = game.item_prototypes
    local output = {}
    local output_index = 0
    local filters = input.filters
    for i = 1, #filters do
      local filter = filters[i]
      if item_prototypes[filter.name] then
        output_index = output_index + 1
        output[output_index] = {name = filter.name, count = filter.count, mode = filter.mode, index = output_index}
      end
    end
    player.infinity_inventory_filters = output
    player.remove_unfiltered_items = input.remove_unfiltered_items
    return true
  end
  return false
end

local function export_filters(player)
  local filters = player.infinity_inventory_filters
  local output = {
    filters = filters,
    remove_unfiltered_items = player.remove_unfiltered_items
  }
  return game.encode_string(
    "EditorExtensions-inventory_filters-"
    ..filters_table_version
    .."-"
    ..game.table_to_json(output)
  )
end

-- GUI

-- string GUI

local function close_string_gui(e)
  local player_table = global.players[e.player_index]
  local refs = player_table.gui.inventory_filters_string
  refs.window.destroy()
  player_table.gui.inventory_filters_string = nil
end

local function update_confirm_button_enabled(e)
  local player_table = global.players[e.player_index]
  local refs = player_table.gui.inventory_filters_string

  if #e.element.text > 0 then
    refs.confirm_button.enabled = true
  else
    refs.confirm_button.enabled = false
  end
end

local function import_filters(e)
  local player = game.get_player(e.player_index)
  local player_table = global.players[e.player_index]
  local refs = player_table.gui.inventory_filters_string

  local string = refs.textbox.text

  if inventory.import_filters(player, string) then
    close_string_gui(e)
    player.create_local_flying_text{
      text = {"ee-message.imported-infinity-filters"},
      create_at_cursor = true
    }
  else
    player.create_local_flying_text{
      text = {"ee-message.invalid-infinity-filters-string"},
      create_at_cursor = true
    }
    player.play_sound{path = "utility/cannot_build", volume_modifier = 0.75}
  end
end

local function open_string_gui(e)
  local player = game.get_player(e.player_index)
  local player_table = global.players[e.player_index]

  -- check for existing filters GUI
  local gui_data = player_table.gui.inventory_filters_string

  if gui_data then
    close_string_gui(e)
  end

  local mode = gui.get_tags(e.element).mode

  -- create GUI
  local refs = gui.build(player.gui.screen, {
    {
      type = "frame",
      direction = "vertical",
      ref = {"window"},
      children = {
        {type = "flow", ref = {"titlebar_flow"}, children = {
          {
            type = "label",
            style = "frame_title",
            caption = {"ee-gui."..mode.."-infinity-filters"},
            ignored_by_interaction = true
          },
          {type = "empty-widget", style = "flib_dialog_titlebar_drag_handle", ignored_by_interaction = true}
        }},
        {type = "frame", style = "inside_shallow_frame_with_padding", children = {
          {
            type = "text-box",
            style_mods = {width = 400, height = 300},
            clear_and_focus_on_right_click = true,
            text = mode == "import" and "" or export_filters(player),
            elem_mods = {word_wrap = true},
            handlers = mode == "import" and {on_text_changed = "inv_update_confirm_button_enabled"} or nil,
            ref = {"textbox"}
          }
        }},
        {type = "flow", style = "dialog_buttons_horizontal_flow", children = {
          {
            type = "button",
            style = "back_button",
            caption = {"gui.cancel"},
            handlers = {on_click = "inv_close_string_gui"}
          },
          {type = "empty-widget", style = "flib_dialog_footer_drag_handle", ref = {"footer_drag_handle"}},
          (
            mode == "import"
            and {
              type = "button",
              style = "confirm_button",
              caption = {"gui.confirm"},
              elem_mods = {enabled = false},
              handlers = {on_click = "inv_import_filters"},
              ref = {"confirm_button"}
            }
            or nil
          )
        }}
      }
    }
  })

  refs.textbox.select_all()
  refs.textbox.focus()

  refs.titlebar_flow.drag_target = refs.window
  refs.footer_drag_handle.drag_target = refs.window

  refs.window.force_auto_center()

  player_table.gui.inventory_filters_string = refs
end

-- buttons GUI

local function close_buttons_gui(e)
  local player_table = global.players[e.player_index]
  local refs = player_table.gui.inventory_filters_buttons
  refs.window.destroy()
  player_table.gui.inventory_filters_buttons = nil
end


gui.add_handlers{
  inv_close_string_gui = close_string_gui,
  inv_update_confirm_button_enabled = update_confirm_button_enabled,
  inv_import_filters = import_filters,
  inv_open_string_gui = open_string_gui
}

function inventory.show_filters_buttons(player)
  local player_table = global.players[player.index]

  -- TODO anchor to character GUI
  local refs = gui.build(player.gui.screen, {
    {type = "frame", style = "quick_bar_window_frame", ref = {"window"}, children = {
      {type = "frame", style = "shortcut_bar_inner_panel", direction = "horizontal", children = {
        {
          type = "sprite-button",
          style = "shortcut_bar_button",
          sprite = "ee_import_inventory_filters",
          tooltip = {"ee-gui.import-infinity-filters"},
          tags = {mode = "import"},
          handlers = {on_click = "inv_open_string_gui"}
        },
        {
          type = "sprite-button",
          style = "shortcut_bar_button",
          sprite = "ee_export_inventory_filters",
          tooltip = {"ee-gui.export-infinity-filters"},
          tags = {mode = "export"},
          handlers = {on_click = "inv_open_string_gui"}
        }
      }}
    }}
  })

  player_table.gui.inventory_filters_buttons = refs
end

function inventory.close_guis(player_index)
  local player_table = global.players[player_index]
  local guis = player_table.gui

  if guis.inventory_filters_string then
    close_string_gui{player_index = player_index}
  end
  if guis.inventory_filters_buttons then
    close_buttons_gui{player_index = player_index}
  end
end

return inventory
