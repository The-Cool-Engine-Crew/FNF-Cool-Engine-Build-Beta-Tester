#pragma header

// rain.frag — shader de lluvia para phillyStreets
// Solo uniforms float (FlxRuntimeShader no soporta bool/int de forma fiable).

uniform float uTime;
uniform float uScale;
uniform float uIntensity;
uniform float uPuddleY;
uniform float uPuddleScaleY;
uniform vec3  uRainColor;
uniform vec2  uScreenResolution; // debe setearse desde el stage script

// ── Hash / ruido ──────────────────────────────────────────────────────────

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// ── Gota individual ───────────────────────────────────────────────────────

float raindrop(vec2 uv, float t) {
    float speed   = 0.6 + hash(uv.x * 43.7) * 0.8;
    float offset  = hash(uv.x * 17.3);
    float y       = fract(uv.y - t * speed + offset);

    float tailLen = 0.15 + hash(uv.x * 31.1) * 0.1;
    float head    = smoothstep(0.08, 0.0, abs(y));
    float tail    = smoothstep(tailLen, 0.0, 1.0 - y);

    return clamp(head + tail * 0.5, 0.0, 1.0);
}

// ── Capa de lluvia ────────────────────────────────────────────────────────

float rainLayer(vec2 uv, float t, vec2 cellSize, float density) {
    vec2  cell   = floor(uv / cellSize);
    vec2  cellUV = fract(uv  / cellSize);

    if (hash2(cell) >= density) return 0.0;

    float xNorm   = cellUV.x * 2.0 - 1.0;
    // FIX: ampliado de 0.18 a 0.35 para gotas más anchas y visibles
    float xFactor = smoothstep(0.35, 0.0, abs(xNorm));
    return raindrop(cellUV, t) * xFactor;
}

// ── Reflejo de charco ─────────────────────────────────────────────────────

float puddleReflection(vec2 screenPx, float t) {
    if (uPuddleScaleY <= 0.0) return 0.0;
    float dy = screenPx.y - uPuddleY;
    if (dy < 0.0) return 0.0;
    float depth = dy * uPuddleScaleY;
    float wave  = sin(depth * 25.0 - t * 3.0) * 0.5 + 0.5;
    return wave * exp(-depth * 1.5) * 0.25;
}

// ── Main ──────────────────────────────────────────────────────────────────

void main() {
    vec4 tex = flixel_texture2D(bitmap, openfl_TextureCoordv);

    if (uIntensity <= 0.0) {
        gl_FragColor = tex;
        return;
    }

    // openfl_TextureCoordv está interpolado [0..1] en toda la pantalla.
    vec2 sc = openfl_TextureCoordv;
    vec2 uv = sc * uScale;           // escalar para densidad de gotas
    float t = uTime;

    // FIX: rain se mantiene en [0..1] — representa el brillo REAL de cada gota.
    // Antes se multiplicaba por uIntensity aquí, y luego otra vez en el mix (*0.6),
    // dejando el factor de mezcla final en solo 6% con intensidad 0.1 → invisible.
    float rain = 0.0;
    rain += rainLayer(uv,        t,        vec2(0.04, 0.10), 0.55) * 1.0;
    rain += rainLayer(uv * 0.7,  t * 0.8,  vec2(0.06, 0.14), 0.45) * 0.7;
    rain += rainLayer(uv * 1.4,  t * 1.2,  vec2(0.03, 0.08), 0.65) * 0.5;
    rain  = clamp(rain, 0.0, 1.0); // brillo completo de la gota individual

    float puddle = puddleReflection(vec2(sc.x * uScreenResolution.x, sc.y * uScreenResolution.y), t) * uIntensity;

    vec3 base = mix(tex.rgb, uRainColor, puddle);

    // FIX: color de gota = blanco-azulado brillante, NO el uRainColor oscuro [0.4,0.5,0.8].
    // uRainColor es correcto para el charco (tinte ambiental), pero las rayas de
    // lluvia deben ser claras para verse sobre cualquier fondo.
    // uIntensity controla la opacidad GLOBAL del efecto (factor de mezcla directo).
    vec3 dropColor = mix(vec3(0.82, 0.91, 1.0), uRainColor, 0.25);
    vec3 result    = mix(base, dropColor, rain * uIntensity);

    gl_FragColor = vec4(result, tex.a);
}
