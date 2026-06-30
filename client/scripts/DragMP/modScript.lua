if extensions and extensions.isExtensionLoaded and extensions.isExtensionLoaded("dragmp") then
  extensions.unload("dragmp")
end

extensions.load("dragmp")
setExtensionUnloadMode("dragmp", "manual")
log("I", "DragMP", "DragMP modScript loaded via scripts/DragMP")

