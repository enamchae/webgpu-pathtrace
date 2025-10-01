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

fn triangle_intersect_t(triangle: Triangle, origin: vec3f, dir: vec3f, normal: vec3f) -> f32 {
    return dot(triangle.a - origin, normal) / dot(dir, normal);
}

const EPSILON: f32 = 1e-2;
const INF: f32 = 99999;

fn triangle_intersect_barycentric(triangle: Triangle, intersection_pt: vec3f) -> vec2f {
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

struct DistanceResult {
    distance: f32,
    normal: vec3f,
    point: vec3f,
}

fn triangle_distance(triangle: Triangle, origin: vec3f, dir: vec3f) -> DistanceResult {
    let normal = triangle_normal(triangle);

    let t = triangle_intersect_t(triangle, origin, dir, normal);
    if t < EPSILON {
        return DistanceResult(INF, normal, vec3f(0, 0, 0));
    }

    let intersection_pt = origin + dir * t;

    let barycentric = triangle_intersect_barycentric(triangle, intersection_pt);
    if barycentric.x < 0 || barycentric.y < 0 || barycentric.x + barycentric.y > 1 {
        return DistanceResult(INF, normal, intersection_pt);
    }

    return DistanceResult(t, normal, intersection_pt);
}

struct IntersectionResult {
    closest_obj_index: u32,
    found: bool,
    intersection: DistanceResult,
}

fn intersect(origin: vec3f, dir: vec3f) -> IntersectionResult {
    var found = false;
    var closest_obj_index = 0u;
    var min_result = DistanceResult(INF, vec3f(0, 0, 0), vec3f(0, 0, 0));

    for (var i = 0u; i < arrayLength(&triangles); i++) {
        let result = triangle_distance(triangles[i], origin, dir);

        if result.distance < min_result.distance {
            found = true;
            closest_obj_index = i;
            min_result = result;
        }
    }
    
    return IntersectionResult(closest_obj_index, found, min_result);
}

fn trace_ray(origin: vec3f, dir: vec3f) -> vec3f {
    var col = vec3f(1, 1, 1);

    var current_origin = origin;
    var current_dir = dir;

    for (var depth = 0u; depth < 20; depth++) {
        let result = intersect(current_origin, current_dir);

        if !result.found {
            return col;
        }

        current_origin = result.intersection.point;
        current_dir = reflect(current_dir, result.intersection.normal);

        col *= vec3f(0.8, 0.9, 0.9);
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