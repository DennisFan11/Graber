shader_type canvas_item;

uniform vec2 pos_circle1 = vec2(50.0, 50.0);
uniform vec2 pos_circle2 = vec2(100.0, 50.0);
uniform vec2 pos_box = vec2(75.0, 100.0);
uniform float box_rotation = 0.0;

uniform float radius_circle1 = 7.0;
uniform float radius_circle2 = 7.0;
uniform vec2 box_half_size = vec2(12.0, 12.0);
uniform float box_corner_radius = 2.5;

uniform float line_thickness = 2.5; 
uniform float V : hint_range(0.0, 50.0, 0.1) = 13.0;

uniform sampler2D color_ramp : hint_default_black; 
uniform float color_spread : hint_range(1.0, 50.0, 0.1) = 10.0;

// 【新增】控制發光強度，用來突破 1.0 觸發 WorldEnvironment 的 Glow 特效
uniform float emission_strength : hint_range(0.0, 10.0, 0.1) = 1.0;

varying vec2 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 rotate_space(vec2 pt, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(pt.x * c + pt.y * s, -pt.x * s + pt.y * c);
}

float circle_sdf(vec2 p, vec2 c, float r) { return length(p - c) - r; }

float rounded_box_sdf(vec2 p, vec2 c, vec2 half_size, float r) {
    vec2 q = abs(p - c) - half_size + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float segment_sdf(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 平滑最大值 (用來做平滑的差集/挖空)
float smax(float a, float b, float k) {
    return -smin(-a, -b, k);
}
void fragment() {
    // 1. 計算所有主體節點的距離
    float d1 = circle_sdf(world_pos, pos_circle1, radius_circle1);
    float d2 = circle_sdf(world_pos, pos_circle2, radius_circle2);
    
    vec2 box_local_pos = world_pos - pos_box;
    vec2 rotated_local_pos = rotate_space(box_local_pos, box_rotation);
    vec2 final_box_pos = rotated_local_pos + pos_box;
    float d3 = rounded_box_sdf(final_box_pos, pos_box, box_half_size, box_corner_radius);
    
    // ==========================================
    // 【修改部分：讓線段只連接到邊緣，不進入中心】
    // ==========================================
    // 計算從圓心到方塊的單位方向
    vec2 dir1 = normalize(pos_box - pos_circle1);
    // 起點：圓心 + 方向 * 圓半徑 (讓起點剛好在圓的邊緣)
    vec2 start1 = pos_circle1 + dir1 * radius_circle1;
    // 終點：方塊中心 - 方向 * 方塊邊界距離 (考慮旋轉與長寬)
    vec2 local_dir1 = rotate_space(-dir1, box_rotation); // 將射線轉入方塊的局部空間
    float dist_box1 = min(abs(box_half_size.x / (local_dir1.x + 1e-6)), abs(box_half_size.y / (local_dir1.y + 1e-6))) + box_corner_radius;
    vec2 end1 = pos_box - dir1 * dist_box1;

    // 同理，處理第二條線
    vec2 dir2 = normalize(pos_box - pos_circle2);
    vec2 start2 = pos_circle2 + dir2 * radius_circle2;
    vec2 local_dir2 = rotate_space(-dir2, box_rotation);
    float dist_box2 = min(abs(box_half_size.x / (local_dir2.x + 1e-6)), abs(box_half_size.y / (local_dir2.y + 1e-6))) + box_corner_radius;
    vec2 end2 = pos_box - dir2 * dist_box2;
    
    // 計算連接線距離 (使用計算好的邊緣起終點)
    float l1 = segment_sdf(world_pos, start1, end1, line_thickness);
    float l2 = segment_sdf(world_pos, start2, end2, line_thickness);
    // ==========================================
    
    // 2. 【計算平滑總形狀】(全部融在一起：圓 + 方塊 + 線)
    float d_smooth = smin(d1, d2, V);
    d_smooth = smin(d_smooth, d3, V);
    d_smooth = smin(d_smooth, l1, V);
    d_smooth = smin(d_smooth, l2, V);
    
    // 3. 【重新定義挖空目標】(只把圓形和方塊算進去，排除線段 l1 和 l2！)
    float d_nodes = min(min(d1, d2), d3);
    
    // 4. 【核心：挖空】拿總形狀「減去」純節點形狀
    float d_final = smax(d_smooth, -d_nodes, 2.0);
    
    // 5. 抗鋸齒 Alpha 與顏色映射
    float alpha = 1.0 - smoothstep(0.0, 1.5, d_final);
    
    float inner_depth = clamp(-d_final / color_spread, 0.0, 1.0);
    vec4 ramp_color = texture(color_ramp, vec2(inner_depth, 0.5));
    
    // 6. 【核心發光：突破 HDR 界線】
    vec3 final_rgb = ramp_color.rgb * emission_strength;
    
    // 最終輸出
    COLOR = vec4(final_rgb, alpha * ramp_color.a);
}