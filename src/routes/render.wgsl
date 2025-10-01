struct Triangle {
    a: vec3f,
    b: vec3f,
    c: vec3f,
}

@group(0)
@binding(0)
var<storage, read> triangles: array<Triangle>;


struct VertexOut {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn vert(
    @location(0) position: vec4f,
) -> VertexOut {
    var output: VertexOut;

    output.position = position;
    output.uv = position.xy;

    return output;
}

fn project_to_screen(pt: vec3f) -> vec2f {
    return pt.xy / pt.z;
}

@fragment
fn frag(
    data: VertexOut,
) -> @location(0) vec4f {
    var col = vec3f(0., 0., 0.);

    for (var i = 0u; i < arrayLength(&triangles); i++) {
        let tri = triangles[i];

        // get offset barycentric basis vectors
        let proj_a = project_to_screen(tri.a);
        let proj_ba = project_to_screen(tri.b) - proj_a;
        let proj_ca = project_to_screen(tri.c) - proj_a;

        let offset_uv = data.uv - proj_a;

        // convert [u, v] in terms of barycentric basis vectors
        let barycentric = mat2x2(
            proj_ca.y, -proj_ba.y,
            -proj_ca.x, proj_ba.x,
        ) * (1 / (proj_ba.x * proj_ca.y - proj_ba.y * proj_ca.x)) * offset_uv;

        let s = barycentric.x;
        let t = barycentric.y;

        if (s > 0 && t >= 0 && s + t <= 1) {
            col.r += s;
            col.g += t;
        }
    }

    return vec4f(col, 1);
}