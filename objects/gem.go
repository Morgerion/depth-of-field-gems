components {
  id: "gem"
  component: "/objects/gem.script"
}
embedded_components {
  id: "mesh"
  type: "mesh"
  data: "material: \"/materials/gem.material\"\n"
  "vertices: \"/geometry/gem_placeholder.buffer\"\n"
  "primitive_type: PRIMITIVE_TRIANGLES\n"
  "position_stream: \"position\"\n"
  "normal_stream: \"normal\"\n"
  ""
}
