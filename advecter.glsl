
#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 16, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script

layout(set = 1, binding = 0, std430) restrict buffer VelocityXOut {
    double data[];
} velocity_x_out;

layout(set = 1, binding = 1, std430) restrict buffer VelocityYOut {
    double data[];
} velocity_y_out;

layout(set = 1, binding = 0, std430) restrict buffer VelocityX {
    double data[];
} velocity_x;

layout(set = 1, binding = 1, std430) restrict buffer VelocityY {
    double data[];
} velocity_y;

layout(set = 1, binding = 2, std430) restrict buffer Solids {
    int data[];
} solids;

layout(set = 2, binding = 0, std140) uniform Param {
    ivec2 grid_size;
    double delta;
};

int is_solid_cell(int x, int y) {
    x = clamp(x, 0, grid_size.x - 1);
    y = clamp(y, 0, grid_size.y - 1);
    int i = y * grid_size.x + x;
    int n = i % 32;
    i /= 32;
    return (solids.data[i] >> n) & 1;
}

double get_velocity_x(int x, int y) {
    x = clamp(x, 0, grid_size.x);
    y = clamp(y, 0, grid_size.y - 1);
    return velocity_x.data[(grid_size.x + 1) * y + x];
}

double get_velocity_y(int x, int y) {
    x = clamp(x, 0, grid_size.x - 1);
    y = clamp(y, 0, grid_size.y);
    return velocity_y.data[(grid_size.x) * y + x];
}

double sample_bilinear_x(vec2 position, vec2 frac) {
    double a_1 = get_velocity_x(position.x, position.y);
    double b_1 = get_velocity_x(position.x + 1, position.y);

    double a_2 = get_velocity_x(position.x, position.y + 1);
    double b_2 = get_velocity_x(position.x + 1, position.y + 1);

    double x = mix(a_1, b_1, frac.x);
    double y = mix(a_2, b_2, frac.x);

    return mix(x, y, frac.y);
}

double sample_bilinear_y(vec2 position, vec2 frac) {
    double a_1 = get_velocity_y(position.x, position.y);
    double b_1 = get_velocity_y(position.x + 1, position.y);

    double a_2 = get_velocity_y(position.x, position.y + 1);
    double b_2 = get_velocity_y(position.x + 1, position.y + 1);

    double x = mix(a_1, b_1, frac.x);
    double y = mix(a_2, b_2, frac.x);

    return mix(x, y, frac.y);
}

vec2 smaple_veloctiy_at_grid_position(vec2 position) {
    if is_solid_cell(position.x, position.y) return vec2(0.0, 0.0);
    vec position_x = pos;
    vec position_y = pos;
    position_x.y -= 0.5;
    position_y.x -= 0.5;

    vec2 frac_x = position_x - position_x.floor();
    vec2 frac_y = position_y - position_y.floor();

    position_x -= frac_x;
    position_y -= frac_y;

    return vec2(sample_bilinear_x(position_x, frac_x), sample_bilinear_y(position_y, frac_y))
}

void main() {
    int i = int(gl_GlobalInvocationID.x);
    if (i > grid_size.x * grid_size.y) return;

    int x = i % (grid_size.x + 1);
    int y = i / (grid_size.x + 1);

    vec2 pos = vec2(x, y + 0.5);
    vec2 pos_mid = vec2(0.0, 0.0);
    if (y < grid_size.y) {
        pos_mid = pos - 0.5 * delta * sample_velocity_at_grid_position(pos);
        pos = pos - delta * sample_velocity_at_grid_position(pos_mid);
        velocity_x_out.data[y * (grid_size.x + 1) + x] = sample_velocity_at_grid_position(pos).x;
    }
    if (x < grid_size.x) {
        pos.x = x + 0.5;
        pos.y = y;
        pos_mid = pos - 0.5 * delta * sample_velocity_at_grid_position(pos);
        pos = pos - delta * sample_velocity_at_grid_position(pos_mid);
        velocity_y_out.data[y * (grid_size.x) + x] = sample_velocity_at_grid_position(pos).y;
    }
}
