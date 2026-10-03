// SIGF kit (frozen, restored by check.ps1 before every compile): compiled right after defs.qc.
// Declares the hooks the patched QuakeC 1.06 calls, and the kit helpers (defined in sigf_pilot.qc).

// TRUE once the map has loaded (the first StartFrame). Precaching is only legal while it is FALSE.
float sigf_started;

// precache_* are the engine builtins renamed in defs.qc (*_builtin). These wrappers make every precache
// after load a no-op instead of a fatal "Precache can only be done in spawn functions" error: a monster
// spawned mid-game by a wave can call its own spawn function. The model or sound must still have been
// precached at load (worldspawn -> SIGF_Precache), otherwise setmodel/sound fails at run time.
string(string s) precache_model = { if (!sigf_started) precache_model_builtin(s); return s; };
string(string s) precache_sound = { if (!sigf_started) precache_sound_builtin(s); return s; };
string(string s) precache_model2 = { if (!sigf_started) precache_model2_builtin(s); return s; };
string(string s) precache_sound2 = { if (!sigf_started) precache_sound2_builtin(s); return s; };

// Hooks the mod defines (sigf.qc):
void() SIGF_Precache;                                 // worldspawn: precache every new model and sound here
void(float wave) SIGF_DemoWave;                       // demo/intermission: stage wave N (self = the player)
void(entity targ, entity attacker) SIGF_OnKilled;     // any monster or player killed (loot drops, death effects)

// Hooks the kit defines (sigf_pilot.qc):
void() SIGF_StartFrame;
void() SIGF_PilotThink;

// Kit helpers (sigf_pilot.qc):
// Spawns a thing <dist> units in front of the player (<side> > 0 = to the right) and runs its spawn function.
entity(string cls, void() spawnfunc, float dist, float side) SIGF_SpawnAhead;
// At load only (SIGF_Precache): runs a spawn function on a throwaway entity so all its precaches happen,
// then removes it. Use it for every monster a wave spawns later, vanilla or new.
void(string cls, void() spawnfunc) SIGF_Preload;
float() SIGF_Mode;                                    // 0 normal play, 1 demo, 2 intermission waves
