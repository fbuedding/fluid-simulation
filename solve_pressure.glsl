#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script
layout(set = 0, binding = 0, std430) restrict buffer PressureSolveData {
    vec2 data[];
}
pressureSolveData;

layout(set = 1, binding = 0, std430) restrict buffer Pressure {
    double data[];
}
pressure;
layout(set = 2, binding = 0, std140) uniform Param {
    ivec2 grid_size;
    int pass_index;
    int half_cell_count;
};

int ceilling_div(int x, int y) {
    return (x + y - 1) / y;
}
ivec2 checkboard_coord(int i) {
    int x = 0;
    int y = 0;
    if (grid_size.x % 2 == 1) {
        int xy = i * 2 + pass_index;
        x = xy % grid_size.x;
        y = xy / grid_size.x;
    } else {
        int cells_per_row = grid_size.x / 2;
        y = i / cells_per_row;
        int col_in_row = i % cells_per_row;

        // Aufgrund des Schachbrettmusters ist der "Start-x" der Farbe abwechselnd 0 und 1 je Zeile
        x = col_in_row * 2 + ((y + pass_index) % 2);
    }
    return ivec2(x, y);
}

double get_pressure(int x, int y) {
    // if (x < 0 || x >= grid_size.x || y < 0 || y >= grid_size.y) return 0.0;
    x = clamp(x, 0, grid_size.x - 1);
    y = clamp(y, 0, grid_size.y - 1);
    return pressure.data[y * grid_size.x + x];
}
void main() {
    int i = int(gl_GlobalInvocationID.x);
    if (i >= half_cell_count) return;
    ivec2 cell = checkboard_coord(i);
    i = grid_size.x * cell.y + cell.x;
    float velocity_term = pressureSolveData.data[i].x;
    int edge_flow = int(pressureSolveData.data[i].y);

    int flow_top = (edge_flow >> 0) & 1;
    int flow_right = (edge_flow >> 1) & 1;
    int flow_bottom = (edge_flow >> 2) & 1;
    int flow_left = (edge_flow >> 3) & 1;

    int edge_flow_count = flow_top + flow_right + flow_bottom + flow_left;
    if (edge_flow_count == 0) return;

    double pressure_top = get_pressure(cell.x - 1, cell.y) * flow_top;
    double pressure_right = get_pressure(cell.x, cell.y + 1) * flow_right;
    double pressure_bottom = get_pressure(cell.x + 1, cell.y) * flow_bottom;
    double pressure_left = get_pressure(cell.x, cell.y - 1) * flow_left;

    double pressure_term = (pressure_top + pressure_right + pressure_bottom + pressure_left) / edge_flow_count;
    double pressure_new = pressure_term - velocity_term;
    double pressure_old = pressure.data[i];
    pressure.data[i] = pressure_old + (pressure_new - pressure_old) * 1.7;
}
