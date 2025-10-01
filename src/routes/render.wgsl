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

fn triangle_normal(triangle: Triangle) -> vec3f {
    return normalize(cross(triangle.b - triangle.a, triangle.c - triangle.a));
}

fn triangle_intersect_t(triangle: Triangle, origin: vec3f, dir: vec3f) -> f32 {
    let normal = triangle_normal(triangle);

    return dot(triangle.a - origin, normal) / dot(dir, normal);
}

const EPSILON: f32 = 1e-2;
const INF: f32 = 99999;

fn triangle_intersect_barycentric(triangle: Triangle, origin: vec3f, dir: vec3f, t: f32) -> vec2f {
    let intersection_pt = origin + dir * t;

    let ba = triangle.b - triangle.a;
    let ca = triangle.c - triangle.a;
    let solution = intersection_pt - triangle.a;
    const DUMMY = vec3f(1, 1, 1); // arbitrary nonzero column vector to get a square matrix for Cramer's rule

    // use Cramer's rule to solve for barycentric coordinates

    let coeffs_determinant = determinant(mat3x3(ba, ca, DUMMY));
    if coeffs_determinant == 0 {
        return vec2f(INF, INF);
    }

    return vec2f(
        determinant(mat3x3(solution, ca, DUMMY)) / coeffs_determinant,
        determinant(mat3x3(ba, solution, DUMMY)) / coeffs_determinant,
    );
}

fn triangle_distance(triangle: Triangle, origin: vec3f, dir: vec3f) -> f32 {
    let t = triangle_intersect_t(triangle, origin, dir);
    if t < EPSILON {
        return INF;
    }

    let barycentric = triangle_intersect_barycentric(triangle, origin, dir, t);
    if barycentric.x < 0 || barycentric.y < 0 || barycentric.x + barycentric.y > 1 {
        return INF;
    }

    return t;
}

struct IntersectionResult {
    closest_obj_index: u32,
    found: bool,
    distance: f32,
}

fn intersect(origin: vec3f, dir: vec3f) -> IntersectionResult {
    var found = false;
    var closest_obj_index = 0u;
    var min_distance = INF;

    for (var i = 0u; i < arrayLength(&triangles); i++) {
        let distance = triangle_distance(triangles[i], origin, dir);

        if distance < min_distance {
            found = true;
            closest_obj_index = i;
            min_distance = distance;
        }
    }
    
    return IntersectionResult(closest_obj_index, found, min_distance);
}

fn trace_ray(origin: vec3f, dir: vec3f) -> vec3f {
    var col = vec3f(0, 0, 0);

    let result = intersect(origin, dir);

    if result.found {
        col.g = 1 / result.distance;
    }

    return col;
}

@fragment
fn frag(
    data: VertexOut,
) -> @location(0) vec4f {
    let dir = normalize(vec3(data.uv, -1));

    return vec4f(trace_ray(vec3f(0, 0, 0), dir), 1);
}