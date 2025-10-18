#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 16, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script

layout(set = 0, binding = 0, std430) restrict buffer PackeData {
    vec2 data[];
} packed_data;

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
    float K;
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

void main() {
    int i = int(gl_GlobalInvocationID.x);
    if (i >= grid_size.x * grid_size.y) return;
    int y = i / grid_size.x;
    int x = i % grid_size.x;
    int is_solid = is_solid_cell(x, y);
    int flow_top = 1 - (is_solid | (is_solid_cell(x, y - 1)));
    int flow_right = 1 - (is_solid | (is_solid_cell(x + 1, y)));
    int flow_bottom = 1 - (is_solid | (is_solid_cell(x, y + 1)));
    int flow_left = 1 - (is_solid | (is_solid_cell(x - 1, y)));

    int packed_edge_flow = flow_top << 0 | flow_right << 1 | flow_bottom << 2 | flow_left << 3;

    double velocity_top = get_velocity_y(x, y);
    double velocity_right = get_velocity_x(x + 1, y);
    double velocity_bottom = get_velocity_y(x, y + 1);
    double velocity_left = get_velocity_x(x, y);

    double velocity_term = 0.0;
    int flow_count = flow_top + flow_right + flow_bottom + flow_left;
    double delta_velocity = velocity_right - velocity_left + velocity_bottom - velocity_top;
    if (flow_count > 0) {
        velocity_term = delta_velocity / (flow_count * K);
    }
    packed_data.data[i] = vec2(velocity_term, packed_edge_flow);
}
