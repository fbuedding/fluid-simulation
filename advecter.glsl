
#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 16, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script

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
}
