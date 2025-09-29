struct VertexOut {
    @builtin(position) position: vec4f,
    @location(0) color: vec4f,
}

@vertex
fn vert(
    @location(0) position: vec4f,
    @location(1) color: vec4f,
) -> VertexOut {
    var output: VertexOut;

    output.position = position;
    output.color = color;

    return output;
}

@fragment
fn frag(
    data: VertexOut,
) -> @location(0) vec4f {
    return data.color;
}