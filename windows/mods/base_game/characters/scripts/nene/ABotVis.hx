/**
 * ABotVis.hx — Script HScript del visualizador de frecuencias del A-Bot.
 *
 * Cargado por nene.hx con:
 *   var vizModule = require('ABotVis.hx');
 *   viz = vizModule.create(baseX, baseY);
 *
 * Usa funkin.vis.dsp.SpectralAnalyzer (haxelib git funkin.vis).
 * Constructor real: new SpectralAnalyzer(audioSource, barCount, smoothing, peakHold)
 *   audioSource = snd._channel.__audioSource  (lime.media.AudioSource)
 *   barCount    = 7
 *   smoothing   = 0.1  (igual que V-Slice)
 *   peakHold    = 40   (igual que V-Slice)
 *
 * En HScript no existe @:privateAccess, pero el acceso reflexivo
 * a campos privados funciona igual sin la anotación.
 */

var BAR_COUNT = 7;

// Offsets acumulativos de posición (igual que ABotVis.hx de V-Slice).
var _offsetX = [0.0, 59.0, 56.0, 66.0, 54.0, 52.0, 51.0];
var _offsetY = [0.0, -8.0, -3.5, -0.4,  0.5,  4.7,  7.0];

// ─────────────────────────────────────────────────────────────────────────────

function create(baseX, baseY)
{
    var bars        = [];
    var analyzer    = null;
    var levelsCache = [];
    var _baseX      = baseX;
    var _baseY      = baseY;

    // Posiciones acumuladas (equivale al .fold(sum) del .hx compilado).
    var cumX = [];
    var cumY = [];
    var cx = 0.0;
    var cy = 0.0;
    for (i in 0...BAR_COUNT)
    {
        cx += _offsetX[i];
        cy += _offsetY[i];
        cumX.push(cx);
        cumY.push(cy);
    }

    // Crear sprites de las barras.
    var visFrms = loadCharacterSparrow('abot/aBotViz');
    for (i in 0...BAR_COUNT)
    {
        var bar = new FunkinSprite(_baseX + cumX[i], _baseY + cumY[i]);
        bar.frames       = visFrms;
        bar.antialiasing = true;
        var idx = i + 1; // viz10, viz20 … viz70
        bar.addAnim('VIZ', 'viz' + idx + '0', 0);
        bar.playAnim('VIZ', false, false, 1);
        bars.push(bar);
    }

    return {

        bars: bars,

        /**
         * Engancha SpectralAnalyzer al instrumental.
         * Llamar desde onSongStart() en nene.hx.
         */
        initAnalyzer: function()
        {
            var snd = FlxG.sound.music;
            if (snd == null)
            {
                log('[ABotVis] initAnalyzer: FlxG.sound.music es null.');
                return;
            }

            // snd._channel.__audioSource es privado en FlxSound.
            // HScript accede por reflexión sin necesitar @:privateAccess.
            var audioSource = snd._channel.__audioSource;
            if (audioSource == null)
            {
                log('[ABotVis] initAnalyzer: audioSource es null.');
                return;
            }

            // Mismos parámetros que V-Slice: smoothing=0.1, peakHold=40.
            analyzer = new funkin.vis.dsp.SpectralAnalyzer(audioSource, BAR_COUNT, 0.1, 40);

            // Tuning idéntico al ABotVis.hx compilado de V-Slice.
            analyzer.minDb   = -65;
            analyzer.maxDb   = -25;
            analyzer.maxFreq = 22000;
            analyzer.minFreq = 10;
            analyzer.fftN    = 256;

            log('[ABotVis] SpectralAnalyzer listo.');
        },

        dumpSound: function()
        {
            analyzer = null;
        },

        update: function(elapsed)
        {
            if (analyzer == null)
            {
                for (bar in bars) bar.visible = false;
                return;
            }

            levelsCache = analyzer.getLevels(levelsCache);

            var len = bars.length < levelsCache.length ? bars.length : levelsCache.length;
            for (i in 0...len)
            {
                var animFrame = (FlxG.sound.volume == 0 || FlxG.sound.muted)
                    ? 0
                    : Math.round(levelsCache[i].value * 6);

                bars[i].visible = animFrame > 0;

                animFrame -= 1;
                if (animFrame < 0) animFrame = 0;
                if (animFrame > 5) animFrame = 5;
                animFrame = Std.int(Math.abs(animFrame - 5)); // flip de Dave

                if (bars[i].animation.curAnim != null)
                    bars[i].animation.curAnim.curFrame = animFrame;
            }
        },

        setBase: function(x, y)
        {
            _baseX = x;
            _baseY = y;
            for (i in 0...bars.length)
            {
                bars[i].x = x + cumX[i];
                bars[i].y = y + cumY[i];
            }
        },

        setVisible: function(v) { for (bar in bars) bar.visible = v; },

        setShader: function(sh) { for (bar in bars) bar.shader = sh; },

        onBeatHit: function(beat) {},

        destroy: function()
        {
            analyzer = null;
            for (bar in bars) bar.destroy();
            bars = [];
        }
    };
}
