// phillyStreets.hx — Stage script para Cool Engine
// Portado desde v-slice (FunkinCrew/Funkin).
//
// Coloca este archivo en:
//   mods/<tu_mod>/stages/phillyStreets/scripts/phillyStreets.hx
//
// Requiere:
//   - assets/shaders/rain.frag  (en el mod o en assets/)
//   - rain.frag en mods/<mod>/shaders/ o assets/shaders/
//   - Elementos en phillyStreets.json:
//       phillyCars        (carro principal, izquierda→derecha)
//       phillyCars_copy   (carro secundario, derecha→izquierda)
//       phillyTraffic     (semáforo, anims: tored / togreen)
//
// ── Diferencias respecto al original V-Slice ─────────────────────────────
//   • getNamedProp()  → stage.getElement()
//   • super.onCreate() → onStageCreate()
//   • super.onUpdate(event) → onUpdate(elapsed)
//   • onBeatHit(event) → onBeatHit(beat:Int)
//   • onPause/onResume/onGameOver/onRestart → mismos nombres
//   • FlxTiledSprite   → FlxBackdrop (scroll infinito de flixel-addons)
//   • FlxG.camera.filters → setFilters(camGame, [...])
//   • FlxTweenUtil.pauseTweensOf → bucle manual con FlxTween.globalManager
//   • PlayState.instance.currentSong.id → SONG.song
//   • Conductor.instance.songPosition   → Conductor.songPosition
// ─────────────────────────────────────────────────────────────────────────────
// Variables de estado
// ─────────────────────────────────────────────────────────────────────────────

// Shader de lluvia vía ShaderManager (carga rain.frag directo, sin RuntimeRainShader)
var RAIN_SHADER = 'rain'; // nombre del archivo rain.frag (sin extensión)
var rainShaderStartIntensity = 0.0;
var rainShaderEndIntensity = 0.0;
var rainTime = 0.0;
var lightsStop = false;
var lastChange = 0;
var changeInterval = 8;
var carWaiting = false;
var carInterruptable = true;
var car2Interruptable = true;
var scrollingSky = null; // FlxBackdrop

// ─────────────────────────────────────────────────────────────────────────────
// onCreate
// ─────────────────────────────────────────────────────────────────────────────

function onStageCreate()
{
	// ── Cielo con scroll infinito ─────────────────────────────────────────
	// FlxBackdrop es el equivalente de FlxTiledSprite en flixel-addons 5.
	// repeatAxes: 0x01 = repetir en X, 0x02 = en Y, 0x03 = ambos.
	scrollingSky = new FlxBackdrop(Paths.imageStage("phillySkybox"), 0x01, 0, 0);
	scrollingSky.setPosition(-650, -375);
	scrollingSky.scrollFactor.set(0.1, 0.1);
	scrollingSky.scale.set(0.65, 0.65);
	scrollingSky.updateHitbox();
	add(scrollingSky);

	// ── Rain shader vía ShaderManager ───────────────────────────────────
	// ShaderManager.scanShaders() ya registró rain.frag desde shaders/.
	// applyShaderToCamera crea la instancia y la registra en _liveInstances
	// para que setShaderParam() la encuentre cada frame.
	ShaderManager.applyShaderToCamera(RAIN_SHADER, camGame);
	ShaderManager.setShaderParam(RAIN_SHADER, 'uScale', FlxG.height / 200.0);
	ShaderManager.setShaderParam(RAIN_SHADER, 'uTime', 0.0);
	rainTime = 0.0;

	var songId = SONG != null ? SONG.song.toLowerCase().replace("-", " ").trim() : "";
	if (songId == "darnell")
	{
		rainShaderStartIntensity = 0.05;
		rainShaderEndIntensity = 0.15;
	}
	else if (songId == "lit up")
	{
		rainShaderStartIntensity = 0.1;
		rainShaderEndIntensity = 0.2;
	}
	else if (songId == "2hot")
	{
		rainShaderStartIntensity = 0.2;
		rainShaderEndIntensity = 0.4;
	}
	else
	{
		rainShaderStartIntensity = 0.1;
		rainShaderEndIntensity = 0.2;
	}

	ShaderManager.setShaderParam(RAIN_SHADER, 'uIntensity', rainShaderStartIntensity);
	ShaderManager.setShaderParam(RAIN_SHADER, 'uRainColor', [0.4, 0.5, 0.8]);
	ShaderManager.setShaderParam(RAIN_SHADER, 'uScreenResolution', [FlxG.width * 1.0, FlxG.height * 1.0]);

	// Aplicar lightmap blend en los elementos del stage que lo necesitan.
	// (blend y alpha ya vienen del JSON — estas líneas son sólo fallback de seguridad)
	var hwLightmap = stage.getElement("phillyHighwayLights_lightmap");
	if (hwLightmap != null && hwLightmap.blend == null)
	{
		hwLightmap.blend = BlendMode.ADD;
		hwLightmap.alpha = 0.6;
	}
	var tfLightmap = stage.getElement("phillyTraffic_lightmap");
	if (tfLightmap != null && tfLightmap.blend == null)
	{
		tfLightmap.blend = BlendMode.ADD;
		tfLightmap.alpha = 0.6;
	}

	// Ajustar puddleY desde el elemento "puddle" si existe en el JSON
	var puddle = stage.getElement("puddle");
	if (puddle != null)
	{
		ShaderManager.setShaderParam(RAIN_SHADER, 'uPuddleY', puddle.y + 80);
		ShaderManager.setShaderParam(RAIN_SHADER, 'uPuddleScaleY', 0.3);
	}

	// ── Estado inicial de coches y semáforo ───────────────────────────────
	resetCar(true, true);
	resetStageValues();
}

// ─────────────────────────────────────────────────────────────────────────────
// onUpdate
// ─────────────────────────────────────────────────────────────────────────────

function onUpdate(elapsed)
{
	rainTime += elapsed;
	ShaderManager.setShaderParam(RAIN_SHADER, 'uTime', rainTime);

	var songLen = (FlxG.sound.music != null && FlxG.sound.music.length > 1000) ? FlxG.sound.music.length : 0.0;
	var songPos = Conductor.songPosition;
	var remapped = (songLen > 0)
		? Math.max(rainShaderStartIntensity, FlxMath.remapToRange(songPos, 0, songLen, rainShaderStartIntensity, rainShaderEndIntensity))
		: rainShaderStartIntensity;
	ShaderManager.setShaderParam(RAIN_SHADER, 'uIntensity', remapped);

	// Scroll del cielo
	if (scrollingSky != null)
		scrollingSky.x -= elapsed * 22;
}

// ─────────────────────────────────────────────────────────────────────────────
// onBeatHit
// ─────────────────────────────────────────────────────────────────────────────

function onBeatHit(beat)
{
	var cars = stage.getElement("phillyCars");
	var cars2 = stage.getElement("phillyCars_copy");

	// Intentar lanzar el carro principal
	if (FlxG.random.bool(10) && beat != (lastChange + changeInterval) && carInterruptable)
	{
		if (!lightsStop)
		{
			driveCar(cars);
		}
		else
		{
			driveCarLights(cars);
		}
	}

	// Intentar lanzar el carro de fondo (solo en verde)
	if (FlxG.random.bool(10) && beat != (lastChange + changeInterval) && car2Interruptable && !lightsStop)
	{
		driveCarBack(cars2);
	}

	// Cambiar semáforo cuando toca
	if (beat == (lastChange + changeInterval))
		changeLights(beat);
}

// ─────────────────────────────────────────────────────────────────────────────
// onPause / onResume
// ─────────────────────────────────────────────────────────────────────────────

function onPause()
{
	pauseCars();
}

function onResume()
{
	resumeCars();
}

// ─────────────────────────────────────────────────────────────────────────────
// onGameOver
// ─────────────────────────────────────────────────────────────────────────────

function onGameOver()
{
	// Quitar el shader para que no tape la pantalla de game over
	clearFilters(camGame);
}

// ─────────────────────────────────────────────────────────────────────────────
// onRestart  (equivale a onSongRetry en v-slice)
// ─────────────────────────────────────────────────────────────────────────────

function onRestart()
{
	resetCar(true, true);
	resetStageValues();
	rainTime = 0.0;
	ShaderManager.setShaderParam(RAIN_SHADER, 'uTime', 0.0);
	ShaderManager.setShaderParam(RAIN_SHADER, 'uIntensity', rainShaderStartIntensity);
	ShaderManager.applyShaderToCamera(RAIN_SHADER, camGame);
}

// ─────────────────────────────────────────────────────────────────────────────
// onDestroy
// ─────────────────────────────────────────────────────────────────────────────

function onDestroy()
{
	var cars = stage.getElement("phillyCars");
	var cars2 = stage.getElement("phillyCars_copy");
	if (cars != null)
		FlxTween.cancelTweensOf(cars);
	if (cars2 != null)
		FlxTween.cancelTweensOf(cars2);
	clearFilters(camGame);
}

// ─────────────────────────────────────────────────────────────────────────────
// Lógica de semáforo
// ─────────────────────────────────────────────────────────────────────────────

function changeLights(beat)
{
	lastChange = beat;
	lightsStop = !lightsStop;

	var traffic = stage.getElement("phillyTraffic");
	if (lightsStop)
	{
		if (traffic != null)
			traffic.animation.play("tored");
		changeInterval = 20;
	}
	else
	{
		if (traffic != null)
			traffic.animation.play("togreen");
		changeInterval = 30;
		if (carWaiting)
			finishCarLights(stage.getElement("phillyCars"));
	}
}

function resetStageValues()
{
	lastChange = 0;
	changeInterval = 8;
	var traffic = stage.getElement("phillyTraffic");
	if (traffic != null)
		traffic.animation.play("togreen");
	lightsStop = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Movimiento de coches
// ─────────────────────────────────────────────────────────────────────────────

function resetCar(left, right)
{
	if (left)
	{
		carWaiting = false;
		carInterruptable = true;
		var cars = stage.getElement("phillyCars");
		if (cars != null)
		{
			FlxTween.cancelTweensOf(cars);
			cars.x = 1200;
			cars.y = 840;
			cars.angle = 0;
			cars.flipX = false;
		}
	}
	if (right)
	{
		car2Interruptable = true;
		var cars2 = stage.getElement("phillyCars_copy");
		if (cars2 != null)
		{
			FlxTween.cancelTweensOf(cars2);
			cars2.x = 1202.5;
			cars2.y = 837.5;
			cars2.angle = 0;
			cars2.flipX = false;
		}
	}
}

// Coche atraviesa la escena sin detenerse (luz verde)
function driveCar(sprite)
{
	if (sprite == null)
		return;
	carInterruptable = false;
	FlxTween.cancelTweensOf(sprite);
	sprite.flipX = false;

	var variant = FlxG.random.int(1, 4);
	sprite.animation.play("car" + variant);

	var extraOffset = [0, 0];
	var duration = 2.0;
	switch (variant)
	{
		case 1:
			duration = FlxG.random.float(1, 1.7);
		case 2:
			extraOffset = [20, -15];
			duration = FlxG.random.float(0.6, 1.2);
		case 3:
			extraOffset = [30, 50];
			duration = FlxG.random.float(1.5, 2.5);
		case 4:
			extraOffset = [10, 60];
			duration = FlxG.random.float(1.5, 2.5);
	}
	var off = [306.6, 168.3];
	sprite.offset.set(extraOffset[0], extraOffset[1]);
	var rotations = [-8, 18];
	var path = [
		FlxPoint.get(1570 - off[0], 1074 - off[1] - 30),
		FlxPoint.get(2400 - off[0], 1005 - off[1] - 50),
		FlxPoint.get(3102 - off[0], 1212 - off[1] + 40)
	];
	FlxTween.angle(sprite, rotations[0], rotations[1], duration, null);
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: null,
		onComplete: function(_)
		{
			carInterruptable = true;
		}
	});
}

// Coche se acerca al semáforo y se detiene (luz roja)
function driveCarLights(sprite)
{
	if (sprite == null)
		return;
	carInterruptable = false;
	FlxTween.cancelTweensOf(sprite);
	sprite.flipX = false;

	var variant = FlxG.random.int(1, 4);
	sprite.animation.play("car" + variant);
	var extraOffset = [0, 0];
	var duration = 2.0;
	switch (variant)
	{
		case 1:
			duration = FlxG.random.float(1, 1.7);
		case 2:
			extraOffset = [20, -15];
			duration = FlxG.random.float(0.9, 1.5);
		case 3:
			extraOffset = [30, 50];
			duration = FlxG.random.float(1.5, 2.5);
		case 4:
			extraOffset = [10, 60];
			duration = FlxG.random.float(1.5, 2.5);
	}
	var off = [306.6, 168.3];
	sprite.offset.set(extraOffset[0], extraOffset[1]);
	var rotations = [-7, -5];
	var path = [
		FlxPoint.get(1500 - off[0] - 20, 1074 - off[1] - 20),
		FlxPoint.get(1770 - off[0] - 80, 1019 - off[1] + 10),
		FlxPoint.get(1950 - off[0] - 80, 1005 - off[1] + 15)
	];
	FlxTween.angle(sprite, rotations[0], rotations[1], duration, {ease: FlxEase.cubeOut});
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: FlxEase.cubeOut,
		onComplete: function(_)
		{
			carWaiting = true;
			if (!lightsStop)
				finishCarLights(stage.getElement("phillyCars"));
		}
	});
}

// El carro sale del semáforo al ponerse verde
function finishCarLights(sprite)
{
	if (sprite == null)
		return;
	carWaiting = false;
	var duration = FlxG.random.float(1.8, 3.0);
	var rotations = [-5, 18];
	var off = [306.6, 168.3];
	var startdelay = FlxG.random.float(0.2, 1.2);
	var path = [
		FlxPoint.get(1950 - off[0] - 80, 1005 - off[1] + 15),
		FlxPoint.get(2400 - off[0], 1005 - off[1] - 50),
		FlxPoint.get(3102 - off[0], 1212 - off[1] + 40)
	];
	FlxTween.angle(sprite, rotations[0], rotations[1], duration, {ease: FlxEase.sineIn, startDelay: startdelay});
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: FlxEase.sineIn,
		startDelay: startdelay,
		onComplete: function(_)
		{
			carInterruptable = true;
		}
	});
}

// Coche de fondo va de derecha a izquierda
function driveCarBack(sprite)
{
	if (sprite == null)
		return;
	car2Interruptable = false;
	FlxTween.cancelTweensOf(sprite);
	sprite.flipX = true;

	var variant = FlxG.random.int(1, 4);
	sprite.animation.play("car" + variant);
	var extraOffset = [0, 0];
	var duration = 2.0;
	switch (variant)
	{
		case 1:
			duration = FlxG.random.float(1, 1.7);
		case 2:
			extraOffset = [20, -15];
			duration = FlxG.random.float(0.6, 1.2);
		case 3:
			extraOffset = [30, 50];
			duration = FlxG.random.float(1.5, 2.5);
		case 4:
			extraOffset = [10, 60];
			duration = FlxG.random.float(1.5, 2.5);
	}
	var off = [306.6, 168.3];
	sprite.offset.set(extraOffset[0], extraOffset[1]);
	var rotations = [18, -8];
	var path = [
		FlxPoint.get(3102 - off[0], 1152 - off[1] + 60),
		FlxPoint.get(2400 - off[0], 1005 - off[1] - 30),
		FlxPoint.get(1570 - off[0], 1074 - off[1] - 10)
	];
	FlxTween.angle(sprite, rotations[0], rotations[1], duration, null);
	FlxTween.quadPath(sprite, path, duration, true, {
		ease: null,
		onComplete: function(_)
		{
			car2Interruptable = true;
		}
	});
}

// ─────────────────────────────────────────────────────────────────────────────
// Pausa/reanuda tweens de los coches
// En flixel 5 no existe FlxTweenUtil, se itera el manager manualmente.
// ─────────────────────────────────────────────────────────────────────────────

function pauseCars()
{
	var cars = stage.getElement("phillyCars");
	var cars2 = stage.getElement("phillyCars_copy");
	FlxTween.globalManager.forEach(function(t)
	{
		if (cars != null && t.object == cars)
			t.active = false;
		if (cars2 != null && t.object == cars2)
			t.active = false;
	});
}

function resumeCars()
{
	var cars = stage.getElement("phillyCars");
	var cars2 = stage.getElement("phillyCars_copy");
	FlxTween.globalManager.forEach(function(t)
	{
		if (cars != null && t.object == cars)
			t.active = true;
		if (cars2 != null && t.object == cars2)
			t.active = true;
	});
}
