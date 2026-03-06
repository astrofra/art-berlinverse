hg = require("harfang")
require("config_gui")
require("utils")

hg.AddAssetsFolder("assets_compiled")

hg.InputInit()
hg.WindowSystemInit()
local audio_initialized = false
if hg.AudioInit then
	hg.AudioInit()
	audio_initialized = true
elseif hg.OpenALInit then
	hg.OpenALInit()
	audio_initialized = true
end

VR_DEBUG_DISPLAY = true
local run_mode = "play"

local characters = {
	{ name = "char_annelore"},
	{ name = "char_georg"},
	{ name = "char_margret"},
	{ name = "char_assistant"},
	{ name = "char_lilith"}
}
local character_idx = 1
local char_change_clock = nil
CHAR_EXPOSE_DURATION_f = 10.0
CHAR_EXPOSE_DURATION = hg.time_from_sec_f(CHAR_EXPOSE_DURATION_f)
CHAR_EXPOSE_DURATION_PAD = CHAR_EXPOSE_DURATION -- hg.time_from_sec_f(CHAR_EXPOSE_DURATION_f + (CHAR_EXPOSE_DURATION_f / 10))

-- local res_x, res_y = 768, 576
-- local res_x, res_y = 800, 600
-- local res_x, res_y = 1920, 1080

local res_x, res_y = 960, 720
local default_window_mode = hg.WV_Fullscreen
local open_vr_enabled = false -- desktop-first default
local language = "en"

run_mode, res_x, res_y, default_window_mode, open_vr_enabled, language = config_gui(res_x, res_y, open_vr_enabled, language)

if run_mode == "cancel" then
	os.exit()
end

local win = hg.NewWindow('Berlinverse', res_x, res_y, 32, default_window_mode) --, hg.WV_Fullscreen)
hg.RenderInit(win)
hg.RenderReset(res_x, res_y, hg.RF_VSync | hg.RF_MSAA4X | hg.RF_MaxAnisotropy)

local pipeline = hg.CreateForwardPipeline(2048, false)
local res = hg.PipelineResources()

--- AAA (to benefit from the render's jittering)
pipeline_aaa_config = hg.ForwardPipelineAAAConfig()
pipeline_aaa = hg.CreateForwardPipelineAAAFromAssets("core", pipeline_aaa_config, hg.BR_Equal, hg.BR_Equal)
pipeline_aaa_config.sample_count = 1

-- VR Stuff

local render_data = hg.SceneForwardPipelineRenderData()  -- this object is used by the low-level scene rendering API to share view-independent data with both eyes

-- OpenVR initialization
if open_vr_enabled and hg.OpenVRInit() then
	open_vr_enabled = true
else
	open_vr_enabled = false
end

local vr_left_fb, vr_right_fb
if open_vr_enabled then
	vr_left_fb = hg.OpenVRCreateEyeFrameBuffer(hg.OVRAA_MSAA4x)
	vr_right_fb = hg.OpenVRCreateEyeFrameBuffer(hg.OVRAA_MSAA4x)
end

-- Create scene
local scene = hg.Scene()
if not hg.LoadSceneFromAssets("main.scn", scene, res, hg.GetForwardPipelineInfo()) then
	error("Failed to load scene: main.scn")
end

-- 3D scene stuff

local i
for i = 1, #characters do
	characters[i].node = scene:GetNode(characters[i].name)
	local sv = characters[i].node:GetInstanceSceneView():GetNode(scene, "character")
	local body = sv:GetInstanceSceneView():GetNode(scene, "body")
	characters[i].material = body:GetObject():GetMaterial(0)
end

-- Setup 2D rendering resources to display eyes textures only when needed.
local quad_model, quad_render_state, eye_t_x, quad_matrix, tex0_program
local quad_uniform_set_value_list, quad_uniform_set_texture_list
if open_vr_enabled and VR_DEBUG_DISPLAY then
	local quad_layout = hg.VertexLayout()
	quad_layout:Begin():Add(hg.A_Position, 3, hg.AT_Float):Add(hg.A_TexCoord0, 3, hg.AT_Float):End()

	quad_model = hg.CreatePlaneModel(quad_layout, 1, 1, 1, 1)
	quad_render_state = hg.ComputeRenderState(hg.BM_Alpha, hg.DT_Disabled, hg.FC_Disabled)

	local eye_t_size = res_x / 2.5
	eye_t_x = (res_x - 2 * eye_t_size) / 6 + eye_t_size / 2
	quad_matrix = hg.TransformationMat4(hg.Vec3(0, 0, 0), hg.Vec3(hg.Deg(90), hg.Deg(0), hg.Deg(0)), hg.Vec3(eye_t_size, 1, eye_t_size))
	tex0_program = hg.LoadProgramFromAssets("shaders/sprite")

	quad_uniform_set_value_list = hg.UniformSetValueList()
	quad_uniform_set_value_list:clear()
	quad_uniform_set_value_list:push_back(hg.MakeUniformSetValue("color", hg.Vec4(1, 1, 1, 1)))

	quad_uniform_set_texture_list = hg.UniformSetTextureList()
end

local camera_node = scene:GetNode("FPSCamera")
scene:SetCurrentCamera(camera_node)

local initial_head_pos = hg.Vec3(0, 0, 0)
if open_vr_enabled then
	initial_head_pos = hg.GetTranslation(camera_node:GetTransform():GetWorld())
	initial_head_pos.y = 0.180
	initial_head_pos.z = initial_head_pos.z - 0.0
end

local keyboard = hg.Keyboard('raw')

if not open_vr_enabled then
	local _rot = camera_node:GetTransform():GetRot()
	-- _rot.y = _rot.y + math.pi / 8.0
	-- _rot.x = _rot.x + math.pi / 16.0
	-- camera_node:GetTransform():SetRot(_rot)
	camera_node:GetCamera():SetFov(math.pi / 3.75)
	scene:SetCurrentCamera(camera_node)
end

local spatial_audio_sources = {
	{ asset = "audio/eerie-portal.ogg", volume = 1.0, yaw_offset = 0.0, distance = 3.5, height = 0.0, sound_ref = -1, source_ref = -1, prev_pos = nil },
	{ asset = "audio/voice-mail-messages.ogg", volume = 1.0, yaw_offset = math.pi, distance = 3.5, height = 0.0, sound_ref = -1, source_ref = -1, prev_pos = nil }
}

if audio_initialized then
	for i = 1, #spatial_audio_sources do
		local src = spatial_audio_sources[i]
		src.sound_ref = hg.LoadOGGSoundAsset(src.asset)
		if src.sound_ref == -1 then
			print("Failed to load spatialized sound asset: " .. src.asset)
		else
			src.source_ref = hg.PlaySpatialized(src.sound_ref, hg.SpatializedSourceState(hg.Mat4.Identity, src.volume, hg.SR_Loop))
			if src.source_ref == -1 then
				print("Failed to play spatialized sound source: " .. src.asset)
			end
		end
	end
end

-- Main loop
local frame_count = 0

-- character change init
char_change_clock = hg.GetClock()
for i = 1, #characters do
	characters[i].node:Disable()
end
local glitch = {0.0, 0.0, 0.0}

while not keyboard:Pressed(hg.K_Escape) and hg.IsWindowOpen(win) do
	keyboard:Update()
	local dt = hg.TickClock()

	-- character exposition logic
	if hg.GetClock() - char_change_clock > CHAR_EXPOSE_DURATION_PAD then
		char_change_clock = hg.GetClock()
		character_idx = character_idx + 1
		if character_idx > #characters then
			character_idx = 1
		end
		print("Changing to '" .. characters[character_idx].name .. "'")

		for i = 1, #characters do
			characters[i].node:Disable()
		end

		characters[character_idx].node:Enable()
	end

	-- fade current character
	local fade_norm_clock = hg.time_to_sec_f(hg.GetClock() - char_change_clock)
	fade_norm_clock = clamp(map(fade_norm_clock, 0.0, CHAR_EXPOSE_DURATION_f, 0.0, 1.0), 0.0, 1.0)

	local fade_q = 0.1
	local fade_char = clamp(map(fade_norm_clock, 0.0, fade_q, 0.0, 1.0), 0.0, 1.0) -- fade in
	fade_char = fade_char * clamp(map(fade_norm_clock, 1.0 - fade_q, 1.0, 1.0, 0.0), 0.0, 1.0) -- fade out

	hg.SetMaterialValue(characters[character_idx].material, "uFadeFX", 
			hg.Vec4(
				clamp(fade_char^0.5 + glitch[1] * fade_char, 0.0, 1.0), -- global fade
				clamp((1.0 - fade_char) + glitch[2] * fade_char, 0.0, 2.0), -- inner transparency
				clamp((1.0 - fade_char)^0.5 + glitch[3] * 10.0, 0.0, 1.0), -- mesh quantization 
				1.0)
			)
	
	local _damp = 0.05
	local j
	for j = 1,3 do
		local r = 0.0
		if (math.random() > 0.95) then
			r = (-1 + 2.0 * math.random())
		end
		glitch[j] = (glitch[j] * (1 - _damp)) + (r * _damp)
	end

	local actor_body_mtx = nil
	if open_vr_enabled then
		actor_body_mtx = hg.TransformationMat4(initial_head_pos, hg.Vec3(0, math.pi, 0))
	end

	if audio_initialized then
		local listener_pos
		local listener_rot_y
		if open_vr_enabled then
			listener_pos = hg.GetT(actor_body_mtx)
			listener_rot_y = hg.GetR(actor_body_mtx).y
		else
			local camera_world = camera_node:GetTransform():GetWorld()
			listener_pos = hg.GetT(camera_world)
			listener_rot_y = hg.GetR(camera_world).y
		end

		local dt_sec_f = math.max(hg.time_to_sec_f(dt), 0.0001)
		for i = 1, #spatial_audio_sources do
			local src = spatial_audio_sources[i]
			if src.source_ref ~= -1 then
				local angle = listener_rot_y + src.yaw_offset
				local src_pos = listener_pos + hg.Vec3(math.sin(angle) * src.distance, src.height, math.cos(angle) * src.distance)
				local src_vel = hg.Vec3(0, 0, 0)
				if src.prev_pos ~= nil then
					src_vel = (src_pos - src.prev_pos) / dt_sec_f
				end
				src.prev_pos = src_pos

				hg.SetSourceTransform(src.source_ref, hg.TranslationMat4(src_pos), src_vel)
			end
		end
	end

	scene:Update(dt)

	-- rendering
	local view_id = 0  -- keep track of the next free view id
	local passId

	-- vr
	if open_vr_enabled then
		local vr_state = hg.OpenVRGetState(actor_body_mtx, 0.05, 1000)
		local left, right = hg.OpenVRStateToViewState(vr_state)

		-- -- Calibration
		-- if keyboard:Released(hg.K_Space) then
		-- 	local physical_head_pos = hg.GetTranslation(vr_state.head)
		-- 	head_pos_offset = initial_head_pos - physical_head_pos
		-- 	-- calibration_local_matrix = hg.InverseFast(head_matrix) * hg.TransformationMat4(calibration_node.GetTransform().GetPos(), calibration_node.GetTransform().GetRot())
		-- end

		passId = hg.SceneForwardPipelinePassViewId()

		-- Prepare view-independent render data once
		view_id, passId = hg.PrepareSceneForwardPipelineCommonRenderData(view_id, scene, render_data, pipeline, res, passId)
		local vr_eye_rect = hg.IntRect(0, 0, vr_state.width, vr_state.height)

		-- Prepare the left eye render data then draw to its framebuffer
		view_id, passId = hg.PrepareSceneForwardPipelineViewDependentRenderData(view_id, left, scene, render_data, pipeline, res, passId)
		view_id, passId = hg.SubmitSceneToForwardPipeline(view_id, scene, vr_eye_rect, left, pipeline, render_data, res, vr_left_fb:GetHandle())

		-- Prepare the right eye render data then draw to its framebuffer
		view_id, passId = hg.PrepareSceneForwardPipelineViewDependentRenderData(view_id, right, scene, render_data, pipeline, res, passId)
		view_id, passId = hg.SubmitSceneToForwardPipeline(view_id, scene, vr_eye_rect, right, pipeline, render_data, res, vr_right_fb:GetHandle())
	else
		view_id, passId = hg.SubmitSceneToPipeline(view_id, scene, hg.IntRect(0, 0, res_x, res_y), true, pipeline, res)
	end

	view_id = view_id + 1

	-- Display the VR eyes texture to the backbuffer
	if VR_DEBUG_DISPLAY and open_vr_enabled then
		hg.SetViewRect(view_id, 0, 0, res_x, res_y)
		local vs = hg.ComputeOrthographicViewState(hg.TranslationMat4(hg.Vec3(0, 0, 0)), res_y, 0.1, 100, hg.ComputeAspectRatioX(res_x, res_y))
		hg.SetViewTransform(view_id, vs.view, vs.proj)

		quad_uniform_set_texture_list:clear()
		quad_uniform_set_texture_list:push_back(hg.MakeUniformSetTexture("s_tex", hg.OpenVRGetColorTexture(vr_left_fb), 0))
		hg.SetT(quad_matrix, hg.Vec3(eye_t_x, 0, 1))
		hg.DrawModel(view_id, quad_model, tex0_program, quad_uniform_set_value_list, quad_uniform_set_texture_list, quad_matrix, quad_render_state)

		quad_uniform_set_texture_list:clear()
		quad_uniform_set_texture_list:push_back(hg.MakeUniformSetTexture("s_tex", hg.OpenVRGetColorTexture(vr_right_fb), 0))
		hg.SetT(quad_matrix, hg.Vec3(-eye_t_x, 0, 1))
		hg.DrawModel(view_id, quad_model, tex0_program, quad_uniform_set_value_list, quad_uniform_set_texture_list, quad_matrix, quad_render_state)
	end

	hg.Frame()

	if open_vr_enabled then
		hg.OpenVRSubmitFrame(vr_left_fb, vr_right_fb)
	end

	hg.UpdateWindow(win)

	-- scene:GarbageCollect()
	-- collectgarbage()
end

hg.DestroyForwardPipeline(pipeline)
if audio_initialized then
	for i = 1, #spatial_audio_sources do
		local src = spatial_audio_sources[i]
		if src.source_ref ~= -1 then
			hg.StopSource(src.source_ref)
		end
		if src.sound_ref ~= -1 then
			hg.UnloadSound(src.sound_ref)
		end
	end
end
if audio_initialized and hg.AudioShutdown then
	hg.AudioShutdown()
end
hg.RenderShutdown()
hg.DestroyWindow(win)
