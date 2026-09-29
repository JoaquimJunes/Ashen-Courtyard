// Rendering-independent evolution rules. The browser build embeds this module.
const ManaEvolution = (() => {
  const profiles = Object.freeze([
    {name:'Start',       manaMax:100, rimRunes:0, crystalRunes:0, circleQuarters:0, auraStrength:0,    connectors:false},
    {name:'Restored',    manaMax:140, rimRunes:1, crystalRunes:0, circleQuarters:0, auraStrength:0,    connectors:false},
    {name:'Awakening',   manaMax:180, rimRunes:2, crystalRunes:0, circleQuarters:0, auraStrength:.22,  connectors:false},
    {name:'Empowered',   manaMax:220, rimRunes:3, crystalRunes:1, circleQuarters:0, auraStrength:.45,  connectors:false},
    {name:'Ascendant',   manaMax:260, rimRunes:4, crystalRunes:2, circleQuarters:0, auraStrength:.7,   connectors:false},
    {name:'Strongest',   manaMax:300, rimRunes:4, crystalRunes:3, circleQuarters:4, auraStrength:1,    connectors:true},
  ].map(Object.freeze));
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));

  function profileFor(unlocked, configuredProfiles=profiles) {
    if (!Number.isInteger(unlocked) || unlocked < 0 || unlocked >= configuredProfiles.length) {
      throw new RangeError('Evolution requires an unlocked reserve count from 0 to 5');
    }
    return configuredProfiles[unlocked];
  }

  // Used by the progression control, not by consumption. Preserve absolute Soul
  // when all vessel capacities grow; retaining old fill fractions would mint Soul.
  // Reducing the level is a preview edit: removed/excess storage is discarded.
  function changeReserves(state, unlocked, configuredProfiles=profiles) {
    const profile = profileFor(unlocked, configuredProfiles);
    if (!Number.isFinite(state.manaMax) || state.manaMax <= 0) throw new RangeError('Invalid prior capacity');
    const reserveFill = Array.from({length:configuredProfiles.length-1}, (_, i) => {
      if (i >= unlocked || i >= state.reserves) return 0;
      const stored = (state.reserveFill[i] || 0) * state.manaMax;
      return clamp(stored / profile.manaMax, 0, 1);
    });
    return {...state, reserves:unlocked, manaMax:profile.manaMax,
      mana:clamp(state.mana, 0, profile.manaMax), reserveFill,
      charges:Math.round(reserveFill.reduce((sum, fill) => sum + fill, 0)*100)/100};
  }

  function resolve(state, displayMana, configuredProfiles=profiles) {
    const profile = profileFor(state.reserves, configuredProfiles);
    const alive = state.health > 0;
    const full = alive && state.mana >= profile.manaMax-1e-9 && displayMana >= profile.manaMax-1e-9;
    return {level:state.reserves, profile, alive, full};
  }

  // This clock observes SoulController.time, so pause and hidden-state handling
  // have one owner. Neither this class nor resolve() can spend or grant resources.
  class Aura {
    constructor(reducedMotion=false) {
      this.reducedMotion = reducedMotion;
      this.reset();
    }
    reset() {
      this.level = -1;
      this.active = false;
      this.startedAt = 0;
      this.stoppedAt = null;
      this.fadeFrom = 0;
      this.last = null;
    }
    sample(evolution, time) {
      if (!Number.isFinite(time) || time < 0) throw new RangeError('Invalid effect time');
      if (evolution.level !== this.level || !evolution.alive || (this.last && time < this.last.time)) {
        this.reset();
        this.level = evolution.level;
      }
      const full = evolution.full;
      const strength = evolution.profile.auraStrength;
      if (full && !this.active) {
        this.startedAt = time;
        this.stoppedAt = null;
      } else if (!full && this.active) {
        this.stoppedAt = time;
        this.fadeFrom = this.last ? this.last.opacity : 0;
      }
      this.active = full;
      const effectAge = Math.max(0, time-this.startedAt);
      const breath = this.reducedMotion ? .5 : .5-.5*Math.cos(effectAge*Math.PI/2);
      const fadeAge = this.stoppedAt === null ? Infinity : Math.max(0, time-this.stoppedAt);
      const residual = evolution.alive && fadeAge < .2 ? this.fadeFrom*(1-fadeAge/.2) : 0;
      const opacity = full ? strength*(.55+.45*breath) : residual;
      const result = {
        emitting:full && strength > 0,
        opacity,
        motion:!this.reducedMotion && evolution.alive,
        effectAge:this.reducedMotion ? 0 : effectAge,
        fadeAge,
        runeEmission:full ? 1 : 0,
        circleEmission:full ? 1 : 0,
        breath,
      };
      this.last = {...result, time};
      return result;
    }
  }
  return Object.freeze({profiles, profileFor, changeReserves, resolve, Aura});
})();
if (typeof module !== 'undefined' && module.exports) module.exports = ManaEvolution;
