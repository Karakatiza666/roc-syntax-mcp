render! = |model, frame| {
	frame.clear!(Color.from_hex_rgb(0x101820))
	frame.circle!({ center: model.pointer, radius: 12, style: Draw.filled(Color.ray_white) })
	Ok({})
}

Model : { pointer : Math.Vec2 }

init! = App.init(App.default, |_io| Ok({ pointer: { x: 0, y: 0 } }))

update! = |_model, input, _io| Ok({ pointer: input.devices.mouse.position() })
