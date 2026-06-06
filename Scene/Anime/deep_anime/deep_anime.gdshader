shader_type canvas_item;

// --- 基礎 SDF 形狀庫 ---
float circle_sdf(vec2 p, vec2 c, float r) {
    return length(p - c) - r;
}

float box_sdf(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + vec2(r);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

// --- 平滑布林運算庫 ---
// 平滑聯集 (加法: A + B)
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 平滑差集 (減法: A - B)
// 用於將某個形狀從主體中平滑地「挖掉」
float smax(float a, float b, float k) {
    return -smin(-a, -b, k);
}

void fragment() {
    // 取得置中的 UV 座標 (以 0.5, 0.5 為中心)
    vec2 p = UV;
    
    // ==========================================
    // 步驟 1：建立所有的獨立 SDF 元件
    // ==========================================
    
    // SDF 1: 頂部的基底矩形 (固定在上方)
    float sdf_top_bar = box_sdf(p - vec2(0.5, 0.1), vec2(0.3, 0.15), 0.05);
    
    // SDF 2: 垂墜在下方的圓形主體 (隨時間上下移動)
    float drop_y = 0.5 + sin(TIME * 2.0) * 0.2; // 上下移動的 Y 座標
    float sdf_bottom_drop = circle_sdf(p, vec2(0.5, drop_y), 0.18);
    
    // SDF 3 & 4: 左右兩側的「負空間圓形」
    // 這兩個圓的目的是為了從主體中「咬掉」兩側，擠出漂亮的收腰曲線
    float sdf_cut_left = circle_sdf(p, vec2(0.15, drop_y - 0.15), 0.25);
    float sdf_cut_right = circle_sdf(p, vec2(0.85, drop_y - 0.15), 0.25);

    // ==========================================
    // 步驟 2：開始合成 (CSG Boolean Operations)
    // ==========================================
    
    // 1. 先將頂部矩形與底部圓形做「平滑加法」，形成一個粗糙的葫蘆狀
    float combined_shape = smin(sdf_top_bar, sdf_bottom_drop, 0.1);
    
    // 2. 利用「平滑減法 (smax)」，用左右兩個大圓把多餘的肉挖掉！
    // 注意：減去的形狀要加上負號 (-sdf_cut_left)
    float final_sdf = smax(-sdf_cut_left, combined_shape, 0.08);
    final_sdf = smax(-sdf_cut_right, final_sdf, 0.08);

    // ==========================================
    // 步驟 3：著色輸出 (還原描邊與顏色)
    // ==========================================
    
    vec3 bg_color = vec3(0.07, 0.1, 0.13);        // 最外層背景
    vec3 liquid_color = vec3(0.1, 0.25, 0.42);    // 深藍色液體
    vec3 stroke_color = vec3(0.3, 0.5, 0.7);      // 邊緣的高光/淺藍色描邊

    // 畫出主體
    float alpha = 1.0 - smoothstep(0.0, 0.005, final_sdf);
    vec3 color = mix(bg_color, liquid_color, alpha);
    
    // 多重 SDF 合成後的內側邊緣描邊 (Stroke)
    float stroke_sdf = abs(final_sdf + 0.01) - 0.002;
    float stroke_mask = (1.0 - smoothstep(0.0, 0.005, stroke_sdf)) * alpha;
    
    color = mix(color, stroke_color, stroke_mask * 0.8);

    COLOR.rgb = color;
    COLOR.a = 1.0;
}