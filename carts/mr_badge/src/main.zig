const std = @import("std");
const cart = @import("cart-api");
const DisplayColor = cart.DisplayColor;

const f32x2 = @Vector(2, f32);
const f32x3 = @Vector(3, f32);
const f32x4 = @Vector(4, f32);
const screen_size: f32x2 = .{ cart.screen_width, cart.screen_height };
const clamp = std.math.clamp;
const geom = @import("mr_geom");
const mr_tween = geom.tween;
const ilerp = mr_tween.interp.ilerp;
const lerp = mr_tween.interp.lerp;
const remap = mr_tween.interp.remap;
const bounceOut = mr_tween.ease.bounceOut;
const elasticOut = mr_tween.ease.elasticOut;
const pow = std.math.pow;
const acos = std.math.acos;

comptime {
    // XXX: what does this do?
    cart.export_start_code();
}

const dt = 1.0 / 30.0;
const period = 1000 * dt;

pub fn start() void {
    // XXX: ...
    // cart.set_vsync_enabled(period);
    cart.set_vsync_dynamic();
}

// XXX: add to mr geom? build in?
fn sign(v: anytype) @TypeOf(v) {
    switch (@typeInfo(@TypeOf(v))) {
        .float => return std.math.sign(v),
        .vector => |info| {
            var result = v;
            inline for (0..info.len) |i| {
                result[i] = std.math.sign(result[i]);
            }
        },
        else => comptime unreachable,
    }
}

fn color(f: f32x3) DisplayColor {
    return .{
        .r = @intFromFloat(f[0] * 31),
        .g = @intFromFloat(f[1] * 63),
        .b = @intFromFloat(f[2] * 31),
    };
}

fn splatColor(f: f32) DisplayColor {
    const rb: u5 = @intFromFloat(f * 31);
    const g: u6 = @intFromFloat(f * 63);
    return .{
        .r = rb,
        .g = g,
        .b = rb,
    };
}

fn sdSample(sd: f32, gradient: f32) f32 {
    const threshold2 = gradient * 0.5;
    return clamp(ilerp(f32, threshold2, -threshold2, sd), 0, 1);
}

fn length(v: anytype) f32 {
    return @sqrt(length2(v));
}

fn length2(v: anytype) f32 {
    return @reduce(.Add, v * v);
}

fn dot(a: anytype, b: anytype) f32 {
    return @reduce(.Add, a * b);
}

fn sdCircle(p: f32x2, radius: f32) f32 {
    return length(p) - radius;
}

// fn sdStar(p: f32x2, radius: f32, points: f32, inner_radius_ratio: f32) f32 {
//     const m: f32 = lerp(f32, points, 2.0, inner_radius_ratio);
//     const an: f32 = std.math.pi / points;
//     const en: f32 = std.math.pi / m;
//     const acs: f32x2 = .{ @cos(an), @sin(an) };
//     const ecs: f32x2 = .{ @cos(en), @sin(en) };

//     const bn: f32 = @mod(atan2(p[0], p[1]), 2.0 * an) - an;
//     var buf: [64]u8 = undefined;
//     cart.trace(std.mem.print(&buf, "t={} {}\n", .{ p[0], p[1] }) catch &buf);
//     var pv = p;
//     pv = @as(f32x2, @splat(length(pv))) * f32x2{ @cos(bn), @abs(@sin(bn)) };
//     pv -= @as(f32x2, @splat(radius)) * acs;
//     pv += ecs * @as(f32x2, @splat(clamp(-dot(pv, ecs), 0.0, radius * acs[1] / ecs[1])));
//     return length(pv) * sign(pv[0]);
// }

fn sdHexagram(p: f32x2, r: f32) f32 {
    var pv = p;
    const k: f32x4 = .{ -0.5, 0.8660254038, 0.5773502692, 1.7320508076 };
    pv = @abs(pv);
    const kxy = geom.swizzle(k, &.{ 0, 1 });
    const kyx = geom.swizzle(k, &.{ 1, 0 });
    pv -= @as(f32x2, @splat(2.0 * @min(dot(kxy, pv), 0.0))) * kxy;
    pv -= @as(f32x2, @splat(2.0 * @min(dot(kyx, pv), 0.0))) * kyx;
    pv -= .{ clamp(pv[0], r * k[2], r * k[3]), r };
    return length(pv) * sign(pv[1]);
}

fn sdPentagram(p: f32x2, r: f32) f32 {
    const k1x = 0.809016994;
    const k2x = 0.309016994;
    const k1y = 0.587785252;
    const k2y = 0.951056516;
    const k1z = 0.726542528;

    var pv = p;

    const v1: f32x2 = .{ k1x, -k1y };
    const v2: f32x2 = .{ -k1x, -k1y };
    const v3: f32x2 = .{ k2x, -k2y };

    pv[0] = @abs(pv[0]);
    pv -= @as(f32x2, @splat(2.0 * @max(dot(v1, pv), 0.0))) * v1;
    pv -= @as(f32x2, @splat(2.0 * @max(dot(v2, pv), 0.0))) * v2;
    pv[0] = @abs(pv[0]);
    pv[1] -= r;
    return length(pv - v3 * @as(f32x2, @splat(clamp(dot(pv, v3), 0.0, k1z * r)))) * sign(geom.outer(f32x2, v3, pv).yx);
}

fn sdHeart(p: f32x2, radius: f32) f32 {
    var pv = p;
    pv /= @splat(radius);
    pv[0] = @abs(pv[0]);
    if (-pv[1] + pv[0] > 0.0) {
        return (length(f32x2{ pv[0], pv[1] } - @as(f32x2, @splat(0.25))) - @sqrt(2.0) / 4.0) * radius;
    }
    return @sqrt(
        @min(
            length2(pv),
            length2(f32x2{ pv[0], 1 - pv[1] } - @as(f32x2, @splat(0.5 * @max(1.0 + pv[0] - pv[1], 0.0)))),
        ),
    ) * sign(pv[0] + pv[1] - 1) * radius;
}

fn sdCoolS(p: f32x2) f32 {
    var pv = p;
    const six: f32 = if (pv[1] < 0.0) -pv[0] else pv[0];
    pv[0] = @abs(pv[0]);
    pv[1] = @abs(pv[1]) - 0.2;
    const rex: f32 = pv[0] - @min(@round(pv[0] / 0.4), 0.4);
    const aby: f32 = @abs(pv[1] - 0.2) - 0.6;

    var d: f32 = length2(f32x2{ six, -pv[1] } - @as(f32x2, @splat(clamp(0.5 * (six - pv[1]), 0.0, 0.2))));
    d = @min(d, length2(f32x2{ pv[0], -aby } - @as(f32x2, @splat(clamp(0.5 * (pv[0] - aby), 0.0, 0.4)))));
    d = @min(d, length2(f32x2{ rex, pv[1] - clamp(pv[1], 0.0, 0.4) }));

    const s: f32 = 2.0 * pv[0] + aby + @abs(aby + 0.4) - 0.4;
    return @sqrt(d) * sign(s);
}

fn sdBlobbyCross(pos: f32x2, size: f32, inset_ratio: f32, round: f32) f32 {
    var posv = pos;
    posv *= @as(f32x2, @splat(2 / size));
    posv = @abs(posv);
    posv = f32x2{ @abs(posv[0] - posv[1]), 1.0 - posv[0] - posv[1] } / @as(f32x2, @splat(@sqrt(2.0)));

    const p = (inset_ratio - posv[1] - 0.25 / inset_ratio) / (6.0 * inset_ratio);
    const q = posv[0] / (inset_ratio * inset_ratio * 16.0);
    const h = q * q - p * p * p;

    var x: f32 = undefined;
    if (h > 0.0) {
        const r = @sqrt(h);
        x = pow(f32, q + r, 1.0 / 3.0) - pow(f32, @abs(q - r), 1.0 / 3.0) * sign(r - q);
    } else {
        const r = @sqrt(p);
        x = 2.0 * r * @cos(acos(q / (p * r)) / 3.0);
    }
    x = @min(x, @sqrt(2.0) / 2.0);

    const z: f32x2 = f32x2{ x, inset_ratio * (1.0 - 2.0 * x * x) } - posv;
    return length(z) * sign(z[1]) / (2 / size) - round;
}

// XXX: swizzle with [0, 1, 2]?
fn sdHexagon(p: f32x2, r: f32) f32 {
    var pv = p;
    const k: f32x3 = .{ -0.866025404, 0.5, 0.577350269 };
    const kxy = geom.swizzle(k, &.{ 0, 1 });
    pv = @abs(pv);
    pv -= @as(f32x2, @splat(2.0 * @min(dot(kxy, pv), 0.0))) * kxy;
    pv -= f32x2{ clamp(pv[0], -k[2] * r, k[2] * r), r };
    return length(pv) * sign(pv[1]);
}

fn sdEquilateralTriangle(p: f32x2, halfWidth: f32) f32 {
    var pv = p;
    const k: f32 = @sqrt(3.0);
    pv[0] = @abs(pv[0]) - halfWidth;
    pv[1] = pv[1] + halfWidth / k;
    if (pv[0] + k * pv[1] > 0.0) {
        pv = f32x2{ pv[0] - k * pv[1], -k * pv[0] - pv[1] } / @as(f32x2, @splat(2));
    }
    pv[0] -= clamp(pv[0], -2.0 * halfWidth, 0.0);
    return -length(pv) * sign(pv[1]);
}

var t: f32 = 0;
var stage: u2 = 0;

fn calcSd(s: u2, p: f32x2) f32 {
    const offset = screen_size / @as(f32x2, @splat(2));
    const r: f32 = 40;
    const hs: f32 = 1.5;
    return switch (s) {
        0 => sdCircle(p - offset, r),
        1 => sdHeart(p - offset + f32x2{ 0, r / hs }, r * hs),
        2 => sdHexagon(p - offset, r),
        3 => sdEquilateralTriangle(p - offset + f32x2{ 0, r / 4 }, r),
        // 3 => sdBlobbyCross(p - offset, r, 0.5, 1),
    };
}

fn opOnion(sdf: f32, r: f32) f32 {
    return @abs(sdf) - r;
}

// XXX: cart.micros_since_boot
pub fn update() void {
    var buf: [64]u8 = undefined;
    cart.trace(std.mem.print(&buf, "t={}\n", .{t}) catch &buf);
    const g: f32 = 1;
    const lbx = 25;
    const lby = 10;
    for (lbx..(screen_size[0] - lbx)) |x| {
        for (lby..screen_size[1] - lby) |y| {
            const p: f32x2 = .{ @floatFromInt(x), @floatFromInt(y) };
            const a = calcSd(stage, p);
            const b = calcSd(stage +% 1, p);
            const sd_fill = lerp(f32, a, b, bounceOut(t));
            const sd_outline = opOnion(sd_fill, 3);
            var result: f32x3 = @splat(0);
            result = lerp(f32x3, result, @splat(1), @splat(sdSample(sd_outline, g)));
            cart.framebuffer[x][y] = color(result);
        }
    }

    t += dt * 2;
    if (t > 1) {
        t = @mod(t, 1);
        stage +%= 1;
    }
}
