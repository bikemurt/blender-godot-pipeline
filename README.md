<img src="addons/blender_godot_pipeline/icon.png" width="64" align="left" />

## blender-godot-pipeline

**Helper Godot 4 addon for my Blender addon which is available on the blender market:**

[Blender Addon](https://blendermarket.com/products/blender-godot-pipeline-addon)

After installing this addon, you'll have easier access to the **GLTF Import** and **Scene Initialization** scripts:

![image](https://github.com/bikemurt/blender-godot-pipeline/assets/23486102/1c952d7f-ba63-4a6f-9a37-70e27d499e91)

_NOTE: This project was started before I really understood `GLTFDocumentExtension` well. [GLTFDocumentExtension](https://docs.godotengine.org/en/stable/classes/class_gltfdocumentextension.html) provides a much better way to parse GLTF files, and .blend file parsing comes natively as a part of Godot's extended pipeline functionality. This addon performs an "ad-hoc" import by scanning the .gltf file and tagging custom import instructions as metadata on Godot nodes. I do encourage people to investigate what I've done here to use it as a basis for their own tooling. It is extremely common that folks adopt and adapt tools for their own processes when making videogames._
