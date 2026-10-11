// Modern, compact, minimalist overlay for Raspberry 3D Viewer with Reel control
(function() {
  function initOverlay() {
    if (!window.raspberry || !window.raspberry.params) {
      setTimeout(initOverlay, 80);
      return;
    }

    // Hide default lil-gui by default to keep the screen ultra clean
    const hideGuiStyle = document.createElement('style');
    hideGuiStyle.textContent = `
      .lil-gui.root {
        display: none !important;
      }
    `;
    document.head.appendChild(hideGuiStyle);

    // Style
    const style = document.createElement('style');
    style.textContent = `
      :root {
        --rv-bg: rgba(18, 18, 20, 0.78);
        --rv-border: rgba(255, 255, 255, 0.08);
        --rv-border-hover: rgba(255, 255, 255, 0.18);
        --rv-text: #f4f4f5;
        --rv-text-muted: #8e8e93;
        --rv-accent: #ffffff;
      }

      /* Compact bottom-center control pill & card */
      #rv-wrapper {
        position: fixed;
        bottom: 24px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 99999;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 8px;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
        user-select: none;
        -webkit-user-select: none;
      }

      /* Preset Segmented Bar */
      #rv-presets-bar {
        display: flex;
        align-items: center;
        background: var(--rv-bg);
        backdrop-filter: blur(28px) saturate(190%);
        -webkit-backdrop-filter: blur(28px) saturate(190%);
        border: 1px solid var(--rv-border);
        border-radius: 999px;
        padding: 3px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.35);
        gap: 2px;
      }

      .rv-seg-btn {
        background: transparent;
        border: none;
        color: var(--rv-text-muted);
        font-size: 11.5px;
        font-weight: 500;
        padding: 5px 12px;
        border-radius: 999px;
        cursor: pointer;
        transition: all 0.16s ease;
        line-height: 1;
      }
      .rv-seg-btn:hover {
        color: var(--rv-text);
      }
      .rv-seg-btn.active {
        background: rgba(255, 255, 255, 0.14);
        color: #ffffff;
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.2);
      }

      .rv-divider {
        width: 1px;
        height: 14px;
        background: var(--rv-border);
        margin: 0 4px;
      }

      .rv-action-btn {
        background: transparent;
        border: none;
        color: var(--rv-text-muted);
        font-size: 11.5px;
        font-weight: 500;
        padding: 5px 11px;
        border-radius: 999px;
        cursor: pointer;
        transition: all 0.16s ease;
      }
      .rv-action-btn:hover {
        color: #ffffff;
        background: rgba(255, 255, 255, 0.08);
      }
      .rv-action-btn.active {
        color: #ffffff;
        background: rgba(255, 255, 255, 0.16);
      }
      .rv-action-btn.active-red {
        color: #fff;
        background: #e11d48;
        box-shadow: 0 0 10px rgba(225, 29, 72, 0.4);
      }

      /* Compact Controls Drawer */
      #rv-card {
        display: none;
        background: var(--rv-bg);
        backdrop-filter: blur(28px) saturate(190%);
        -webkit-backdrop-filter: blur(28px) saturate(190%);
        border: 1px solid var(--rv-border);
        border-radius: 16px;
        padding: 14px 18px;
        width: 320px;
        box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
        animation: rvFadeUp 0.18s cubic-bezier(0.16, 1, 0.3, 1);
      }

      @keyframes rvFadeUp {
        from { opacity: 0; transform: translateY(6px); }
        to { opacity: 1; transform: translateY(0); }
      }

      .rv-field {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 10px;
        font-size: 11.5px;
      }
      .rv-field:last-child {
        margin-bottom: 0;
      }
      .rv-label {
        color: var(--rv-text-muted);
        font-weight: 400;
      }

      /* Minimal Slider */
      .rv-slider {
        -webkit-appearance: none;
        appearance: none;
        width: 140px;
        height: 3px;
        border-radius: 2px;
        background: rgba(255, 255, 255, 0.16);
        outline: none;
        transition: background 0.15s;
      }
      .rv-slider::-webkit-slider-thumb {
        -webkit-appearance: none;
        appearance: none;
        width: 13px;
        height: 13px;
        border-radius: 50%;
        background: #ffffff;
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
        cursor: pointer;
        transition: transform 0.1s;
      }
      .rv-slider::-webkit-slider-thumb:hover {
        transform: scale(1.15);
      }

      /* Color Dot */
      .rv-color-dot-wrapper {
        position: relative;
        width: 20px;
        height: 20px;
        border-radius: 50%;
        overflow: hidden;
        border: 1px solid rgba(255, 255, 255, 0.2);
        cursor: pointer;
      }
      .rv-color-input {
        position: absolute;
        top: -10px;
        left: -10px;
        width: 40px;
        height: 40px;
        opacity: 0;
        cursor: pointer;
      }
      .rv-color-preview {
        width: 100%;
        height: 100%;
        background: #111111;
        border-radius: 50%;
      }

      /* Compact Switch */
      .rv-switch {
        position: relative;
        display: inline-block;
        width: 28px;
        height: 16px;
      }
      .rv-switch input {
        opacity: 0;
        width: 0;
        height: 0;
      }
      .rv-slider-track {
        position: absolute;
        cursor: pointer;
        inset: 0;
        background: rgba(255, 255, 255, 0.15);
        transition: 0.2s cubic-bezier(0.16, 1, 0.3, 1);
        border-radius: 999px;
      }
      .rv-slider-track:before {
        position: absolute;
        content: "";
        height: 12px;
        width: 12px;
        left: 2px;
        bottom: 2px;
        background-color: #ffffff;
        transition: 0.2s cubic-bezier(0.16, 1, 0.3, 1);
        border-radius: 50%;
        box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
      }
      .rv-switch input:checked + .rv-slider-track {
        background: rgba(255, 255, 255, 0.7);
      }
      .rv-switch input:checked + .rv-slider-track:before {
        transform: translateX(12px);
        background-color: #121214;
      }

      /* Code Modal */
      #rv-code-modal {
        position: fixed;
        inset: 36px;
        z-index: 100000;
        background: rgba(14, 14, 16, 0.96);
        backdrop-filter: blur(32px);
        -webkit-backdrop-filter: blur(32px);
        border: 1px solid var(--rv-border);
        border-radius: 14px;
        box-shadow: 0 24px 60px rgba(0, 0, 0, 0.7);
        display: none;
        flex-direction: column;
        overflow: hidden;
        color: #f4f4f5;
      }
      #rv-code-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 18px;
        border-bottom: 1px solid var(--rv-border);
        background: rgba(255, 255, 255, 0.02);
      }
      #rv-code-tabs {
        display: flex;
        gap: 4px;
      }
      .rv-tab-btn {
        background: transparent;
        border: none;
        color: var(--rv-text-muted);
        padding: 5px 12px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: 500;
        cursor: pointer;
        transition: 0.15s;
      }
      .rv-tab-btn:hover {
        color: #fff;
      }
      .rv-tab-btn.active {
        background: rgba(255, 255, 255, 0.1);
        color: #fff;
      }
      #rv-code-body {
        flex: 1;
        overflow: auto;
        padding: 16px 20px;
        background: #090a0d;
      }
      #rv-code-pre {
        margin: 0;
        font-family: "SF Mono", Menlo, Consolas, monospace;
        font-size: 12px;
        line-height: 1.6;
        color: #cbd5e1;
        white-space: pre;
      }
    `;
    document.head.appendChild(style);

    // Code contents
    const codeMetal = `// BerryShaders.metal - Metal Shading Language for iOS/macOS
#include <metal_stdlib>
using namespace metal;

struct BerryVertexIn {
    float3 position   [[attribute(0)]];
    float3 normal     [[attribute(1)]];
    float2 uv         [[attribute(2)]];
    float4 color      [[attribute(3)]];
    float3 center     [[attribute(4)]]; // 3D center of drupelet
};

struct BerryVertexOut {
    float4 position [[position]];
    float2 uv;
    float3 modelPos;
    float3 worldPos;
    float3 normalModel;
    float3 center;
};

struct Light {
    float3 direction;
    float3 color;
};

struct BerryUniforms {
    float4x4 mvp;
    float3x3 modelRotation;
    float3   cameraPos;
    Light    lights[3];
    float3   tint;
    float    sss;
    float    beadGlow;
    float3   transColor;
    float    transDepth;
    float    roughnessScale;
    float    roughnessBias;
    float    aoPower;
    float    tScale[9];
    float3   innerPos;
    float3   innerColor;
    float    innerWall;
};

inline float3 decodeTransfer(float4 sample, float scale) {
    float3 v = sample.rgb * 2.0 - 1.0;
    return sign(v) * v * v * scale;
}

fragment float4 berryFragmentShader(BerryVertexOut in [[stage_in]],
                                    constant BerryUniforms &u [[buffer(0)]],
                                    texture2d<float> tORM     [[texture(0)]],
                                    texture2d<float> tT0      [[texture(1)]],
                                    texture2d<float> tT1      [[texture(2)]],
                                    texture2d<float> tT2      [[texture(3)]],
                                    texture2d<float> tT3      [[texture(4)]],
                                    sampler s [[sampler(0)]])
{
    float3 orm = tORM.sample(s, in.uv).rgb;
    float ao = pow(orm.r, u.aoPower);
    
    // 1. Precomputed Radiance Transfer (Spherical Harmonics)
    float3 sss = decodeTransfer(tT0.sample(s, in.uv), u.tScale[0]) * 0.282095;
    sss += decodeTransfer(tT1.sample(s, in.uv), u.tScale[1]) * 0.488603;
    sss += decodeTransfer(tT2.sample(s, in.uv), u.tScale[2]) * 0.488603;
    sss += decodeTransfer(tT3.sample(s, in.uv), u.tScale[3]) * 0.488603;
    sss = max(sss * u.sss * u.tint, float3(0.0));

    // 2. Beer-Lambert Turbid Bead Translucency
    float3 toC = in.center - in.modelPos;
    float beadR = max(length(toC), 1e-3);
    float3 nS = -toC / beadR;
    float3 sigma = -log(clamp(u.transColor, float3(0.002), float3(0.999))) / u.transDepth;

    float3 bead = float3(0.0);
    for (int i = 0; i < 3; i++) {
        float3 Lm = transpose(u.modelRotation) * u.lights[i].direction;
        float nl = dot(nS, Lm);
        float chord = 2.0 * beadR * max(-nl, 0.0) + 0.10;
        float past = smoothstep(0.45, -0.30, nl);
        bead += u.lights[i].color * exp(-sigma * chord) * past;
    }
    bead *= u.beadGlow * (0.3 + 0.7 * ao);

    // 3. Inner Cavity Lamp
    float3 core = float3(0.0);
    if (dot(u.innerColor, float3(1.0)) > 0.0) {
        float3 toL = u.innerPos - in.modelPos;
        float d2 = max(dot(toL, toL), 1e-4);
        float chord = u.innerWall * (1.0 - orm.b);
        core = u.innerColor * exp(-sigma * chord) / (4.0 * 3.14159 * d2);
    }

    return float4(sss + bead + core, 1.0);
}`;

    const codeSwift = `// MetalRenderer.swift - Swift MetalKit Pipeline
import MetalKit
import simd

public class MetalBerryRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    public var settings: BerrySettings
    
    public init(device: MTLDevice, settings: BerrySettings) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.settings = settings
        super.init()
        buildPipeline()
    }
    
    private func buildPipeline() {
        guard let lib = device.makeDefaultLibrary() else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "berryVertexShader")
        desc.fragmentFunction = lib.makeFunction(name: "berryFragmentShader")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        desc.depthAttachmentPixelFormat = .depth32Float
        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let desc = view.currentRenderPassDescriptor,
              let pipeline = pipelineState else { return }
        let cmd = commandQueue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: desc)!
        enc.setRenderPipelineState(pipeline)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}`;

    // Root Wrapper
    const wrapper = document.createElement('div');
    wrapper.id = 'rv-wrapper';

    // Top: Preset Segmented Bar
    const presetsBar = document.createElement('div');
    presetsBar.id = 'rv-presets-bar';

    const presets = [
      { id: 'Studio', label: 'Studio' },
      { id: 'Lantern', label: 'Lantern' },
      { id: 'Ember', label: 'Ember' },
      { id: 'Dark', label: 'Dark' },
      { id: 'Backlit', label: 'Backlit' },
      { id: 'Neon', label: 'Neon' }
    ];

    presets.forEach((p, idx) => {
      const btn = document.createElement('button');
      btn.className = 'rv-seg-btn' + (idx === 0 ? ' active' : '');
      btn.textContent = p.label;
      btn.onclick = () => {
        document.querySelectorAll('#rv-presets-bar .rv-seg-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        if (window.raspberry?.preset) {
          window.raspberry.preset(p.id);
        }
      };
      presetsBar.appendChild(btn);
    });

    const divider1 = document.createElement('div');
    divider1.className = 'rv-divider';
    presetsBar.appendChild(divider1);

    // Play / Stop Reel button
    const reelBtn = document.createElement('button');
    reelBtn.className = 'rv-action-btn';
    reelBtn.id = 'rv-reel-btn';
    reelBtn.textContent = 'Play Reel';
    reelBtn.onclick = () => {
      if (window.raspberry?.reel?.active) {
        window.raspberry.stopReel?.();
      } else {
        window.raspberry.playReel?.();
      }
      updateReelStatus();
    };
    presetsBar.appendChild(reelBtn);

    function updateReelStatus() {
      const active = !!window.raspberry?.reel?.active;
      if (active) {
        reelBtn.textContent = 'Stop Reel';
        reelBtn.classList.add('active-red');
      } else {
        reelBtn.textContent = 'Play Reel';
        reelBtn.classList.remove('active-red');
      }
    }

    // Monitor reel status periodically
    setInterval(updateReelStatus, 250);

    // Adjust button
    const adjustBtn = document.createElement('button');
    adjustBtn.className = 'rv-action-btn';
    adjustBtn.textContent = 'Adjust';
    adjustBtn.onclick = () => {
      const card = document.getElementById('rv-card');
      const isVisible = card.style.display === 'block';
      card.style.display = isVisible ? 'none' : 'block';
      adjustBtn.classList.toggle('active', !isVisible);
    };
    presetsBar.appendChild(adjustBtn);

    // Code button
    const codeBtn = document.createElement('button');
    codeBtn.className = 'rv-action-btn';
    codeBtn.textContent = 'Code';
    codeBtn.onclick = () => {
      document.getElementById('rv-code-modal').style.display = 'flex';
      window.rvSetTab('metal');
    };
    presetsBar.appendChild(codeBtn);

    wrapper.appendChild(presetsBar);

    // Bottom Card: Clean Adjustments
    const card = document.createElement('div');
    card.id = 'rv-card';
    card.innerHTML = `
      <div class="rv-field">
        <span class="rv-label">Key Light</span>
        <input type="range" class="rv-slider" id="rv-key-slider" min="0" max="8" step="0.1" value="3.5">
      </div>
      <div class="rv-field">
        <span class="rv-label">Cavity Glow</span>
        <input type="range" class="rv-slider" id="rv-core-slider" min="0" max="15" step="0.1" value="0">
      </div>
      <div class="rv-field">
        <span class="rv-label">Translucency</span>
        <input type="range" class="rv-slider" id="rv-trans-slider" min="0" max="3" step="0.05" value="1.2">
      </div>
      <div class="rv-field">
        <span class="rv-label">Background</span>
        <div class="rv-color-dot-wrapper">
          <div class="rv-color-preview" id="rv-bg-dot"></div>
          <input type="color" class="rv-color-input" id="rv-bg-input" value="#111111">
        </div>
      </div>
      <div class="rv-field">
        <span class="rv-label">Fuzz</span>
        <label class="rv-switch">
          <input type="checkbox" id="rv-fuzz-toggle" checked>
          <span class="rv-slider-track"></span>
        </label>
      </div>
      <div class="rv-field">
        <span class="rv-label">Spin</span>
        <label class="rv-switch">
          <input type="checkbox" id="rv-spin-toggle">
          <span class="rv-slider-track"></span>
        </label>
      </div>
    `;
    wrapper.appendChild(card);
    document.body.appendChild(wrapper);

    // Wire Card Controls
    setTimeout(() => {
      const keySlider = document.getElementById('rv-key-slider');
      keySlider.oninput = (e) => {
        if (window.raspberry?.params) {
          window.raspberry.params.lights.key.intensity = parseFloat(e.target.value);
          window.raspberry.apply();
        }
      };

      const coreSlider = document.getElementById('rv-core-slider');
      coreSlider.oninput = (e) => {
        if (window.raspberry?.params) {
          window.raspberry.params.lights.inner.intensity = parseFloat(e.target.value);
          if (parseFloat(e.target.value) > 0 && !window.raspberry.params.lights.inner.color) {
            window.raspberry.params.lights.inner.color = '#ff6020';
          }
          window.raspberry.apply();
        }
      };

      const transSlider = document.getElementById('rv-trans-slider');
      transSlider.oninput = (e) => {
        if (window.raspberry?.params) {
          window.raspberry.params.skin.beadGlow = parseFloat(e.target.value);
          window.raspberry.apply();
        }
      };

      const bgInput = document.getElementById('rv-bg-input');
      const bgDot = document.getElementById('rv-bg-dot');
      bgInput.oninput = (e) => {
        bgDot.style.background = e.target.value;
        if (window.raspberry?.params) {
          window.raspberry.params.environment.background = e.target.value;
          window.raspberry.apply();
        }
      };

      const fuzzToggle = document.getElementById('rv-fuzz-toggle');
      fuzzToggle.onchange = (e) => {
        if (window.raspberry?.params) {
          window.raspberry.params.fuzz.visible = e.target.checked;
          window.raspberry.apply();
        }
      };

      let spinInterval = null;
      const spinToggle = document.getElementById('rv-spin-toggle');
      spinToggle.onchange = (e) => {
        if (e.target.checked) {
          spinInterval = setInterval(() => {
            if (window.raspberry?.controls) {
              window.raspberry.controls.azimuth += 0.015;
            }
          }, 16);
        } else {
          clearInterval(spinInterval);
        }
      };
    }, 200);

    // Code Modal
    const modal = document.createElement('div');
    modal.id = 'rv-code-modal';
    modal.innerHTML = `
      <div id="rv-code-header">
        <div id="rv-code-tabs">
          <button class="rv-tab-btn active" onclick="window.rvSetTab('metal')">BerryShaders.metal</button>
          <button class="rv-tab-btn" onclick="window.rvSetTab('swift')">MetalRenderer.swift</button>
        </div>
        <div style="display:flex;gap:6px;">
          <button class="rv-action-btn" id="rv-copy-code-btn" onclick="window.rvCopyCode()">Copy</button>
          <button class="rv-action-btn" onclick="document.getElementById('rv-code-modal').style.display='none'">Close</button>
        </div>
      </div>
      <div id="rv-code-body">
        <pre id="rv-code-pre"></pre>
      </div>
    `;
    document.body.appendChild(modal);

    window.rvSetTab = function(tab) {
      document.querySelectorAll('.rv-tab-btn').forEach(b => b.classList.remove('active'));
      const pre = document.getElementById('rv-code-pre');
      if (tab === 'metal') {
        document.querySelectorAll('.rv-tab-btn')[0].classList.add('active');
        pre.textContent = codeMetal;
      } else {
        document.querySelectorAll('.rv-tab-btn')[1].classList.add('active');
        pre.textContent = codeSwift;
      }
    };

    window.rvCopyCode = function() {
      const code = document.getElementById('rv-code-pre').textContent;
      navigator.clipboard.writeText(code).then(() => {
        const btn = document.getElementById('rv-copy-code-btn');
        btn.textContent = 'Copied';
        setTimeout(() => btn.textContent = 'Copy', 1200);
      });
    };
  }

  if (document.readyState === 'complete') {
    initOverlay();
  } else {
    window.addEventListener('load', initOverlay);
  }
})();
