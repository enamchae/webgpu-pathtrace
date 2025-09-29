struct VertexOut {
    @builtin(position) position: vec4f,
}

@vertex
fn vert(
    @location(0) position: vec4f,
) -> VertexOut {
    var output: VertexOut;

    output.position = position;

    return output;
}

@fragment
fn frag(
    data: VertexOut,
) -> @location(0) vec4f {
    return vec4f(0., 0., 0., 1.);
}