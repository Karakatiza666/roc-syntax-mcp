## Shaders and 3D: a shader whose uniforms are a Roc record, and a perspective
## camera for textured triangles.
##
## The uniform record is the schema and the values. Pass the starting values to
## `Shader.from_source!` (or `Shader.from_store!`), and the host checks the
## record against the compiled GLSL once: a field the shader does not declare,
## or one of a different type, is an error from the load. Each frame, `render!`
## pairs the model's shader with the current values using the pure
## `with_uniforms`, and `frame.with_shader!` uploads the whole record before
## the draws in its scope. A 0.10 program that resolved each uniform by name
## with `shader.uniform_f32!("time")` and set it with `set!` has no equivalent
## here. `Draw.Shader` and every `uniform_*!` are gone.
##
## A uniform field is `F32`, `I32`, `Bool`, `Math.Vec2`, `Math.Vec3`,
## `Math.Vec4`, `Color.Rgba` (uploaded as a normalized `vec4`) or
## `Assets.Texture`. A nested record is `UnsupportedUniformType`.
##
## `Camera.perspective` makes a `Camera.Camera3D`, and `frame.with_camera_3d!`
## draws inside it with depth testing. Like `with_camera!` it can answer
## `ScopeLimit`, so `render!` lists the tag.
app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.11.1/4NWnSt7bKCyVx4xDFH89pV11ekYbiGQ43kdjfZ9NBJQn.tar.zst" }

import rr.App
import rr.Assets
import rr.Camera
import rr.Color
import rr.Draw
import rr.Math
import rr.Shader

Uniforms : { tint : Color.Rgba, time : F32 }

Model : {
	shader : Shader(Uniforms),
	texture : Draw.Texture,
	seconds : F32,
}

Msg : []

program = { init!, update!, render! }

fragment_source : Str
fragment_source =
	\\#version 330
	\\in vec2 fragTexCoord;
	\\in vec4 fragColor;
	\\uniform sampler2D texture0;
	\\uniform vec4 tint;
	\\uniform float time;
	\\out vec4 finalColor;
	\\void main()
	\\{
	\\    vec4 texel = texture(texture0, fragTexCoord) * fragColor;
	\\    finalColor = texel * tint * (0.8 + 0.2 * sin(time * 3.0));
	\\}

## Loading a shader is refused in `render!`, so it happens here. An empty
## vertex source selects raylib's default stage. The error set names the load
## errors this call can raise, including the uniform ones.
init! : App.Init(Model, [ShaderLoadFailed, ResourceLimit, UniformNotFound(Str), UniformReflectionUnavailable, UniformTypeMismatch({ name : Str, expected : Shader.ShaderUniformType, actual : Shader.ShaderUniformType }), UnsupportedUniformType(Str), TextureGenerationFailed])
init! = App.init(
	App.default.with_title("Topic: shader").with_size({ width: 800, height: 600 }),
	|_io| {
		shader = Shader.from_source!(
			{ vertex_source: "", fragment_source },
			{ tint: Color.white, time: 0 },
		)?
		texture = Assets.generate_checked_texture!({ width: 64, height: 64, checks_x: 8, checks_y: 8, color_a: Color.orange, color_b: Color.white })?
		Ok({ shader, texture, seconds: 0 })
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, [Exit(I64)])
update! = |model, input, _io| Ok({ ..model, seconds: model.seconds + input.time.elapsed_seconds })

render! : Model, Draw.Frame => Try({}, [Exit(I64), ScopeLimit, ScopeUnavailable])
render! = |model, frame| {
	frame.clear!(Color.black)

	camera = Camera.perspective({
		position: Math.vec3(0, 2, 6),
		target: Math.vec3(0, 0, 0),
		up: Math.vec3(0, 1, 0),
		fovy: 60,
	})

	# A shader scope wraps the draws that should use it. The record is replaced
	# with a pure call, not mutated.
	frame.with_shader!(
		model.shader.with_uniforms({ tint: Color.from_hex_rgb(0xffcc88), time: model.seconds }),
		|shaded| {
			shaded.with_camera_3d!(
				camera,
				|scene| {
					scene.textured_triangles_3d!({
						texture: model.texture,
						vertices: [
							{ position: Math.vec3(-2, 0, 0), uv: { x: 0, y: 1 }, tint: Color.white },
							{ position: Math.vec3(2, 0, 0), uv: { x: 1, y: 1 }, tint: Color.white },
							{ position: Math.vec3(0, 3, 0), uv: { x: 0.5, y: 0 }, tint: Color.white },
						],
						indices: [0, 1, 2],
					})
					Ok({})
				},
			)
		},
	)?

	Ok({})
}
