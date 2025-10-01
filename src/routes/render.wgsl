const PI = 3.1415926;
const REV = 2 * PI;
const PI_2 = PI / 2;
const PI_4 = PI / 4;
const SQRT_1_3 = 1 / sqrt(3);


struct Triangle {
    a: vec3f,
    b: vec3f,
    c: vec3f,
}

@group(0)
@binding(0)
var<storage, read> triangles: array<Triangle>;


struct Material {
    diffuse: vec4f,
    emissive: vec4f,
}

@group(0)
@binding(1)
var<storage, read> materials: array<Material>;


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

const EPSILON: f32 = 1e-5;
const INF: f32 = pow(2, 126);

fn triangle_intersect_barycentric(triangle: Triangle, intersection_pt: vec3f) -> vec2f {
    let ba = triangle.b - triangle.a;
    let ca = triangle.c - triangle.a;
    let solution = intersection_pt - triangle.a;
    let dummy = cross(ba, ca); // arbitrary nonzero column vector to get a square matrix for Cramer's rule

    // use Cramer's rule to solve for barycentric coordinates

    let coeffs_determinant = determinant(mat3x3(ba, ca, dummy));
    if coeffs_determinant == 0 {
        return vec2f(INF, INF);
    }

    return vec2f(
        determinant(mat3x3(solution, ca, dummy)) / coeffs_determinant,
        determinant(mat3x3(ba, solution, dummy)) / coeffs_determinant,
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

fn xxhash32_3d(p: vec3u) -> u32 {
    let p2 = 2246822519u; let p3 = 3266489917u;
    let p4 = 668265263u; let p5 = 374761393u;
    var h32 =  p.z + p5 + p.x*p3;
    h32 = p4 * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 += p.y * p3;
    h32 = p4 * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 = p2 * (h32^(h32 >> 15));
    h32 = p3 * (h32^(h32 >> 13));
    return h32^(h32 >> 16);
}
fn rand33(f: vec3f) -> vec3f { return vec3f(xxhash32_3d(bitcast<vec3u>(f))) / f32(0xffffffff); }

fn sample_cosine_weighted_hemisphere(uniform_samples: vec2f, normal: vec3f) -> vec3f {
    // sample a point on the unit sphere's top half
    let z = uniform_samples.x;
    let band_radius = sqrt(1 - z * z);
    let angle = uniform_samples.y * REV;

    // construct a coordinate system achievable by rotating some world axis to the given normal
    var basis_comparator: vec3f;
    if abs(normal.x) < SQRT_1_3 {
        basis_comparator = vec3f(1, 0, 0);
    }
    else if abs(normal.y) < SQRT_1_3 {
        basis_comparator = vec3f(0, 1, 0);
    }
    else {
        basis_comparator = vec3f(0, 0, 1);
    }

    // these just need to be orthonormal to the normal
    let cross1 = normalize(cross(normal, basis_comparator));
    let cross2 = normalize(cross(normal, cross1));

    return mat3x3(cross1, cross2, normal) * vec3f(band_radius * cos(angle), band_radius * sin(angle), z);
}

fn diffuse_reflect(normal: vec3f, dir: vec3f, seed: vec3f) -> vec3f {
    let uniform_samples = rand33(seed);

    let hemispere_point = sample_cosine_weighted_hemisphere(uniform_samples.xy, normal);

    if sign(dot(hemispere_point, normal)) == sign(dot(hemispere_point, dir)) {
        return -hemispere_point;
    } else {
        return hemispere_point;
    }
}

fn env(dir: vec3f) -> vec3f {
    return vec3f(0.97, 0.95, 1);
}

fn trace_ray(origin: vec3f, dir: vec3f, seed: vec3f) -> vec3f {
    var col = vec3f(1, 1, 1);

    var current_origin = origin;
    var current_dir = dir;

    for (var depth = 0u; depth < 250; depth++) {
        let result = intersect(current_origin, current_dir);

        if !result.found {
            return col * env(current_dir);
        }

        current_origin = result.intersection.point;
        // current_dir = reflect(current_dir, result.intersection.normal);
        current_dir = diffuse_reflect(result.intersection.normal, current_dir, seed);


        let material = materials[result.closest_obj_index];
        if material.emissive.a > 0 {
            return material.emissive.rgb;
        }

        col *= material.diffuse.rgb;
    }

    return vec3(0, 0, 0);
}

fn sample_rays(origin: vec3f, dir: vec3f, uv: vec2f) -> vec3f {
    var col = vec3f(0, 0, 0);

    for (var n_sample = 0u; n_sample < 40; n_sample++) {
        col = mix(col, trace_ray(origin, dir, vec3f(uv, f32(n_sample))), 1 / (f32(n_sample) + 1));
    }

    return col;
}

@fragment
fn frag(
    data: VertexOut,
) -> @location(0) vec4f {
    let radius = length(data.uv);
    let angle = atan2(data.uv.y, data.uv.x);

    // let dir = normalize(vec3(data.uv, -1));

    // for lens-like rendering, the UV radius determines the angle change along a sphere
    // the UV angle is just used to rotate the direction vector into place, which is what the matrix does
    let dir = mat3x3(
        cos(angle), -sin(angle), 0,
        sin(angle), cos(angle), 0,
        0, 0, 1,
    ) * vec3f(sin(radius), 0, -cos(radius));

    let linear_col = vec4f(sample_rays(vec3f(0, 0, 0), dir, data.uv), 1);

    return vec4f(
        pow(linear_col.x, 1 / 2.2),
        pow(linear_col.y, 1 / 2.2),
        pow(linear_col.z, 1 / 2.2),
        1,
    );
}