// Graphics quality and adaptive resolution.
// Screens range from a 6" phone to a 12" tablet, so resolution is set by a pixel budget, not by devicePixelRatio:
// a big high-density tablet would otherwise render 3-4 million pixels per frame through bloom and shadows.

export const TIERS = {
  high: { label: 'High', pixels: 2.1e6, bloom: true, shadow: 2048, soft: true, particles: 1 },
  medium: { label: 'Medium', pixels: 1.3e6, bloom: true, shadow: 1024, soft: false, particles: 0.8 },
  low: { label: 'Low', pixels: 0.7e6, bloom: false, shadow: 1024, soft: false, particles: 0.55 },
};

export const quality = {
  setting: 'auto', // 'auto' | 'high' | 'medium' | 'low'
  tier: TIERS.medium,
  tierId: 'medium',
  scale: 1, // auto mode multiplies the pixel budget by this, 0.45..1.25
  // rolling frame-time stats for auto mode
  _acc: 0, _frames: 0, _good: 0, _cool: 0,

  init(setting) {
    this.setting = setting || 'auto';
    if (this.setting === 'auto') {
      // start from a guess based on the device: big screens and weak GPUs begin lower
      const px = window.screen.width * window.screen.height * (window.devicePixelRatio || 1) ** 2;
      // tablets usually carry stronger GPUs; start high with a trimmed budget and let auto settle
      this.tierId = 'high';
      this.scale = px > 4e6 ? 0.85 : 1;
    } else { this.tierId = this.setting; this.scale = 1; }
    this.tier = TIERS[this.tierId];
  },

  // CSS-pixel width/height -> pixel ratio that fits the budget
  pixelRatio(w, h) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2.5);
    const budget = this.tier.pixels * this.scale;
    const fit = Math.sqrt(budget / (w * h));
    return Math.max(0.5, Math.min(dpr, fit));
  },

  // Called every frame in auto mode. Returns true when the resolution should be re-applied.
  sample(dt) {
    if (this.setting !== 'auto') return false;
    this._acc += dt; this._frames++;
    if (this._cool > 0) this._cool -= dt;
    if (this._acc < 1.5) return false;
    const fps = this._frames / this._acc;
    this._acc = 0; this._frames = 0;
    if (this._cool > 0) return false;
    if (fps < 42) {
      this._good = 0; this._cool = 2.5;
      if (this.scale > 0.6) { this.scale = Math.max(0.6, this.scale * 0.82); return true; }
      if (this.tierId === 'high') { this.tierId = 'medium'; this.tier = TIERS.medium; this.scale = 1; return 'tier'; }
      if (this.tierId === 'medium') { this.tierId = 'low'; this.tier = TIERS.low; this.scale = 1; return 'tier'; }
      if (this.scale > 0.45) { this.scale = Math.max(0.45, this.scale * 0.85); return true; }
    } else if (fps > 57) {
      this._good++;
      if (this._good >= 3 && this.scale < 1.15) { this._good = 0; this._cool = 3; this.scale = Math.min(1.15, this.scale * 1.1); return true; }
    } else this._good = 0;
    return false;
  },
};
