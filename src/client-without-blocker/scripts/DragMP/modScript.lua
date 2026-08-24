if extensions and extensions.isExtensionLoaded and extensions.isExtensionLoaded("dragmp") then
  extensions.unload("dragmp")
end

extensions.load("dragmp")
setExtensionUnloadMode("dragmp", "manual")
extensions.load("dragmpTrackResolver")
setExtensionUnloadMode("dragmpTrackResolver", "manual")
log("I", "DragMP", "DragMP modScript loaded via scripts/DragMP")

