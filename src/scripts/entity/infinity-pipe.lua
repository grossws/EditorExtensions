local infinity_pipe = {}

local constants = require("scripts.constants")

function infinity_pipe.snap(entity, player_settings)
  local neighbours = entity.neighbours[1]
  local own_id = entity.unit_number
  -- settings
  local assembler_snapping = player_settings.infinity_pipe_assembler_snapping
  local pipe_snapping = player_settings.infinity_pipe_snapping

  if assembler_snapping or pipe_snapping then
    for i = 1, #neighbours do
      local neighbour = neighbours[i]
      local fb = neighbour.fluidbox
      if fb then
        -- snap to adjacent assemblers
        if assembler_snapping and neighbour.type == "assembling-machine" then
          for j = 1, #fb do
            local connections = fb.get_connections(j)
            if
              connections[1]
              and connections[1].owner.unit_number == own_id
              and fb.get_prototype(j).production_type == "input"
            then
              local fluid = fb.get_locked_fluid(1)
              if fluid then
                -- set to fill the pipe with the fluid
                entity.set_infinity_pipe_filter{name=fluid, percentage=1, mode="exactly"}
              end
              return -- break
            end
          end
        -- snap to locked fluid
        elseif pipe_snapping and constants.pipe_snapping_types[neighbour.type] then
          local fluid = fb[1]
          if fluid then
            -- set filter to that fluid, but don't do anything with it
            entity.set_infinity_pipe_filter{name=fluid.name, percentage=0, mode="at-least"}
            return -- break
          end
        end
      end
    end
  end
end

return infinity_pipe