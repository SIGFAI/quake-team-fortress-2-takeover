// Team Fortress 2 Takeover: RED mercenaries (Heavy, Scout, Soldier, Pyro) invade Quake.
// Critical hits, rocket knockback, burning, a friendly Engineer sentry gun (impulse 50) and hats that drop from the dead.

.float sigf_burst;
.float sigf_say_at;
.float sigf_until;
.float sigf_hats;
.float sigf_streak;
.float sigf_last_kill;
.entity sigf_burner;
.entity sigf_sentry;

// ---------- helpers ----------
void(vector org, float color, float count) sigf_puff =
{
    particle(org, '0 0 40', color, count);
};

void(vector org) sigf_boom_fx =
{
    WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
    WriteByte(MSG_BROADCAST, TE_EXPLOSION);
    WriteCoord(MSG_BROADCAST, org_x);
    WriteCoord(MSG_BROADCAST, org_y);
    WriteCoord(MSG_BROADCAST, org_z);
};

void(string snd) sigf_say =
{
    if (time < self.sigf_say_at)
        return;
    self.sigf_say_at = time + 5 + random() * 4;
    sound(self, CHAN_VOICE, snd, 1, ATTN_NORM);
};

string(entity e) sigf_name =
{
    if (e.classname == "monster_sigf_heavy")
        return "Heavy";
    if (e.classname == "monster_sigf_scout")
        return "Scout";
    if (e.classname == "monster_sigf_soldier")
        return "Soldier";
    if (e.classname == "monster_sigf_pyro")
        return "Pyro";
    return "monster";
};

// ---------- burning: the Pyro's flames and the player's rockets set things on fire ----------
void() sigf_burn_think =
{
    if (!self.enemy || self.enemy.health <= 0 || time > self.sigf_until)
    {
        remove(self);
        return;
    }
    setorigin(self, self.enemy.origin + '0 0 -10');
    self.frame = 1 - self.frame;
    sigf_puff(self.enemy.origin + '0 0 16', 232, 12);
    if (self.enemy.classname == "player")
        T_Damage(self.enemy, self, self.owner, 1);
    else
        T_Damage(self.enemy, self, self.owner, 3);
    self.nextthink = time + 0.3;
};

void(entity targ, entity attacker) sigf_ignite =
{
    local entity b;
    if (!(targ.flags & (FL_MONSTER | FL_CLIENT)) || targ.health <= 0)
        return;
    b = targ.sigf_burner;
    if (b.classname == "sigf_burn" && b.enemy == targ)
    {
        b.sigf_until = time + 3;
        return;
    }
    b = spawn();
    b.classname = "sigf_burn";
    b.owner = attacker;
    b.enemy = targ;
    b.movetype = MOVETYPE_NONE;
    b.solid = SOLID_NOT;
    setmodel(b, "progs/flame2.mdl");
    setorigin(b, targ.origin + '0 0 -10');
    b.effects = EF_DIMLIGHT;
    b.sigf_until = time + 3;
    b.think = sigf_burn_think;
    b.nextthink = time + 0.1;
    targ.sigf_burner = b;
};

// ---------- critical hits: the player's hits sometimes crit for triple damage ----------
float(entity targ, entity inflictor, entity attacker, float damage) SIGF_Crit =
{
    if (targ.classname == "player" && (SIGF_Mode() == 1 || SIGF_Mode() == 2))
        return 0;                      // the demo player is invincible: no red screen either
    if (attacker.classname != "player" || !(targ.flags & FL_MONSTER))
        return damage;
    if (inflictor.classname == "sigf_burn" || targ.health <= 0)
        return damage;
    if (random() > 0.25)
        return damage;
    sigf_puff(targ.origin + '0 0 24', 232, 40);
    sigf_puff(targ.origin + '0 0 24', 73, 30);
    sound(targ, CHAN_ITEM, "sigf/crit.wav", 1, ATTN_NORM);
    sigf_boom_fx(targ.origin + '0 0 20');
    stuffcmd(attacker, "bf\n");
    centerprint(attacker, "* * *  CRITICAL HIT!!!  * * *");
    return damage * 3;
};

// A rocket exploded: it flings the player (rocket jump) and sets monsters nearby on fire.
void(entity missile) SIGF_Boom =
{
    local entity e;
    local float d;
    e = findradius(missile.origin, 150);
    while (e)
    {
        d = vlen(e.origin - missile.origin);
        if (e.classname == "player")
        {
            e.velocity = e.velocity + normalize(e.origin + '0 0 20' - missile.origin) * (150 - d) * 5;
            e.flags = e.flags - (e.flags & FL_ONGROUND);
        }
        else if (missile.owner.classname == "player" && (e.flags & FL_MONSTER))
            sigf_ignite(e, missile.owner);
        e = e.chain;
    }
};

// ---------- loot: hats and sandvichs ----------
void() sigf_hat_touch =
{
    if (other.classname != "player")
        return;
    other.sigf_hats = other.sigf_hats + 1;
    T_Heal(other, 10, 0);
    sound(other, CHAN_ITEM, "sigf/hatpop.wav", 1, ATTN_NORM);
    sigf_puff(self.origin, 192, 30);
    stuffcmd(other, "bf\n");
    centerprint(other, "NEW HAT!  Hats: ", ftos(other.sigf_hats), "\nYou look fabulous.");
    remove(self);
};

void(vector org) sigf_drop_hat =
{
    local entity h;
    h = spawn();
    h.classname = "sigf_hat";
    h.movetype = MOVETYPE_TOSS;
    h.solid = SOLID_TRIGGER;
    setmodel(h, "progs/sigf_hat.mdl");
    setsize(h, '-14 -14 -8', '14 14 24');
    setorigin(h, org + '0 0 40');
    h.velocity_x = crandom() * 120;
    h.velocity_y = crandom() * 120;
    h.velocity_z = 320;
    h.avelocity = '0 280 0';
    h.effects = EF_DIMLIGHT;
    h.touch = sigf_hat_touch;
    h.nextthink = time + 14;
    h.think = SUB_Remove;
};

void() sigf_sandvich_touch =
{
    if (other.classname != "player")
        return;
    if (!T_Heal(other, 50, 0))
        return;
    sound(other, CHAN_ITEM, "sigf/munch.wav", 1, ATTN_NORM);
    stuffcmd(other, "bf\n");
    sprint(other, "Sandvich! +50 health\n");
    remove(self);
};

void(vector org) sigf_drop_sandvich =
{
    local entity s;
    s = spawn();
    s.classname = "sigf_sandvich";
    s.movetype = MOVETYPE_TOSS;
    s.solid = SOLID_TRIGGER;
    setmodel(s, "progs/sigf_sandvich.spr");
    setsize(s, '-14 -14 0', '14 14 24');
    setorigin(s, org + '0 0 20');
    s.velocity_x = crandom() * 80;
    s.velocity_y = crandom() * 80;
    s.velocity_z = 250;
    s.effects = EF_DIMLIGHT;
    s.touch = sigf_sandvich_touch;
    s.nextthink = time + 12;
    s.think = SUB_Remove;
};

// ---------- every merc wears a big silly top hat (it drops as a pickup when they die) ----------
void() sigf_headhat_think =
{
    if (!self.owner || self.owner.health <= 0)
    {
        remove(self);
        return;
    }
    setorigin(self, self.owner.origin + '0 0 1' * self.sigf_until);
    self.angles_y = self.owner.angles_y;
    self.nextthink = time + 0.03;
};

void(float top) sigf_wear_hat =
{
    local entity h;
    h = spawn();
    h.classname = "sigf_headhat";
    h.owner = self;
    h.movetype = MOVETYPE_NONE;
    h.solid = SOLID_NOT;
    setmodel(h, "progs/sigf_hathead.mdl");
    setorigin(h, self.origin + '0 0 1' * top);
    h.sigf_until = top;
    h.think = sigf_headhat_think;
    h.nextthink = time + 0.05;
};

// ---------- the Heavy: slow, tough, a minigun that chews through a burst ----------
void() heavy_stand1 = [0, heavy_stand2] { ai_stand(); };
void() heavy_stand2 = [1, heavy_stand1] { ai_stand(); };
void() heavy_walk1 = [2, heavy_walk2] { ai_walk(5); };
void() heavy_walk2 = [3, heavy_walk3] { ai_walk(5); };
void() heavy_walk3 = [4, heavy_walk4] { ai_walk(5); };
void() heavy_walk4 = [5, heavy_walk1] { ai_walk(5); };
void() heavy_run1 = [2, heavy_run2] { ai_run(9); };
void() heavy_run2 = [3, heavy_run3] { ai_run(9); };
void() heavy_run3 = [4, heavy_run4] { ai_run(9); };
void() heavy_run4 = [5, heavy_run1] { ai_run(9); };

void() heavy_shoot =
{
    local vector dir;
    ai_face();
    makevectors(self.angles);
    dir = normalize(self.enemy.origin - self.enemy.velocity * 0.1 - self.origin);
    FireBullets(2, dir, '0.12 0.12 0');
    self.effects = self.effects | EF_MUZZLEFLASH;
    particle(self.origin + v_forward * 34 + '0 0 6', dir * 40, 192, 8);
};

void() heavy_atk1 = [6, heavy_atk2] { sigf_say("sigf/heavy_say.wav"); ai_face(); self.sigf_burst = 0; sound(self, CHAN_WEAPON, "sigf/minigun.wav", 1, ATTN_NORM); };
void() heavy_atk2 = [7, heavy_atk3] { heavy_shoot(); };
void() heavy_atk3 = [8, heavy_atk4] { heavy_shoot(); };
void() heavy_atk4 = [9, heavy_run1]
{
    heavy_shoot();
    self.sigf_burst = self.sigf_burst + 1;
    if (self.sigf_burst < 4)
        self.think = heavy_atk2;
};

void() heavy_pain1 = [10, heavy_pain2] { };
void() heavy_pain2 = [11, heavy_run1] { };
void(entity attacker, float damage) heavy_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 1.2;
    sound(self, CHAN_VOICE, "player/pain3.wav", 1, ATTN_NORM);
    heavy_pain1();
};

void() heavy_die1 = [12, heavy_die2] { };
void() heavy_die2 = [13, heavy_die3] { self.solid = SOLID_NOT; };
void() heavy_die3 = [14, heavy_die4] { };
void() heavy_die4 = [15, heavy_die5] { };
void() heavy_die5 = [16, heavy_die5] { };
void() heavy_die =
{
    if (self.health < -40)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowHead("progs/gib3.mdl", self.health);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "player/death1.wav", 1, ATTN_NORM);
    heavy_die1();
};

void() monster_sigf_heavy =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    precache_model("progs/sigf_heavy.mdl");
    precache_sound("sigf/minigun.wav");
    precache_sound("sigf/heavy_say.wav");
    precache_sound("player/pain3.wav");
    precache_sound("player/death1.wav");
    precache_sound("player/udeath.wav");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_heavy.mdl");
    setsize(self, '-16 -16 -24', '16 16 48');
    self.health = 200;
    self.th_stand = heavy_stand1;
    self.th_walk = heavy_walk1;
    self.th_run = heavy_run1;
    self.th_missile = heavy_atk1;
    self.th_pain = heavy_pain;
    self.th_die = heavy_die;
    walkmonster_start();
    sigf_wear_hat(66);
};

// ---------- the Scout: fast, hops at you and bats you ----------
void() scout_stand1 = [0, scout_stand2] { ai_stand(); };
void() scout_stand2 = [1, scout_stand1] { ai_stand(); };
void() scout_walk1 = [2, scout_walk2] { ai_walk(8); };
void() scout_walk2 = [3, scout_walk3] { ai_walk(8); };
void() scout_walk3 = [4, scout_walk4] { ai_walk(8); };
void() scout_walk4 = [5, scout_walk1] { ai_walk(8); };

void() scout_hop =
{
    if (random() < 0.12 && (self.flags & FL_ONGROUND) && vlen(self.enemy.origin - self.origin) > 160)
    {
        makevectors(self.angles);
        self.flags = self.flags - (self.flags & FL_ONGROUND);
        self.velocity = v_forward * 320 + '0 0 260';
        sound(self, CHAN_VOICE, "sigf/hatpop.wav", 0.6, ATTN_NORM);
    }
};

void() scout_run1 = [2, scout_run2] { ai_run(24); scout_hop(); };
void() scout_run2 = [3, scout_run3] { ai_run(24); };
void() scout_run3 = [4, scout_run4] { ai_run(24); };
void() scout_run4 = [5, scout_run1] { ai_run(24); };

void() scout_swing =
{
    local vector d;
    ai_charge(8);
    d = self.enemy.origin - self.origin;
    if (vlen(d) < 80)
    {
        sound(self, CHAN_WEAPON, "sigf/bat.wav", 1, ATTN_NORM);
        T_Damage(self.enemy, self, self, 10 + random() * 8);
        sigf_puff(self.enemy.origin + '0 0 16', 64, 15);
    }
};

void() scout_atk1 = [6, scout_atk2] { sigf_say("sigf/scout_say.wav"); ai_charge(6); };
void() scout_atk2 = [7, scout_atk3] { ai_charge(6); };
void() scout_atk3 = [8, scout_atk4] { scout_swing(); };
void() scout_atk4 = [9, scout_run1] { ai_charge(4); };

void() scout_pain1 = [10, scout_pain2] { };
void() scout_pain2 = [11, scout_run1] { };
void(entity attacker, float damage) scout_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 0.8;
    sound(self, CHAN_VOICE, "player/pain1.wav", 1, ATTN_NORM);
    scout_pain1();
};

void() scout_die1 = [12, scout_die2] { };
void() scout_die2 = [13, scout_die3] { self.solid = SOLID_NOT; };
void() scout_die3 = [14, scout_die4] { };
void() scout_die4 = [15, scout_die5] { };
void() scout_die5 = [16, scout_die5] { };
void() scout_die =
{
    if (self.health < -30)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowHead("progs/gib3.mdl", self.health);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "player/death2.wav", 1, ATTN_NORM);
    scout_die1();
};

void() monster_sigf_scout =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    precache_model("progs/sigf_scout.mdl");
    precache_sound("sigf/bat.wav");
    precache_sound("sigf/scout_say.wav");
    precache_sound("sigf/hatpop.wav");
    precache_sound("player/pain1.wav");
    precache_sound("player/death2.wav");
    precache_sound("player/udeath.wav");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_scout.mdl");
    setsize(self, '-16 -16 -24', '16 16 36');
    self.health = 70;
    self.th_stand = scout_stand1;
    self.th_walk = scout_walk1;
    self.th_run = scout_run1;
    self.th_melee = scout_atk1;
    self.th_pain = scout_pain;
    self.th_die = scout_die;
    walkmonster_start();
    sigf_wear_hat(50);
};

// ---------- the Soldier: fires rockets that explode and knock you around ----------
void() sold_stand1 = [0, sold_stand2] { ai_stand(); };
void() sold_stand2 = [1, sold_stand1] { ai_stand(); };
void() sold_walk1 = [2, sold_walk2] { ai_walk(6); };
void() sold_walk2 = [3, sold_walk3] { ai_walk(6); };
void() sold_walk3 = [4, sold_walk4] { ai_walk(6); };
void() sold_walk4 = [5, sold_walk1] { ai_walk(6); };
void() sold_run1 = [2, sold_run2] { ai_run(12); };
void() sold_run2 = [3, sold_run3] { ai_run(12); };
void() sold_run3 = [4, sold_run4] { ai_run(12); };
void() sold_run4 = [5, sold_run1] { ai_run(12); };

void() sold_rocket_touch =
{
    if (other == self.owner)
        return;
    if (pointcontents(self.origin) == CONTENT_SKY)
    {
        remove(self);
        return;
    }
    if (other.health)
        T_Damage(other, self, self.owner, 30);
    T_RadiusDamage(self, self.owner, 40, other);
    self.origin = self.origin - 8 * normalize(self.velocity);
    SIGF_Boom(self);
    sigf_boom_fx(self.origin);
    BecomeExplosion();
};

void() sold_fire =
{
    local entity m;
    local vector dir;
    ai_face();
    sound(self, CHAN_WEAPON, "weapons/sgun1.wav", 1, ATTN_NORM);
    makevectors(self.angles);
    dir = normalize(self.enemy.origin - self.enemy.velocity * 0.15 - self.origin);
    m = spawn();
    m.owner = self;
    m.classname = "sigf_rocket";
    m.movetype = MOVETYPE_FLYMISSILE;
    m.solid = SOLID_BBOX;
    setmodel(m, "progs/missile.mdl");
    setsize(m, '0 0 0', '0 0 0');
    setorigin(m, self.origin + v_forward * 20 + '0 0 12');
    m.velocity = dir * 650;
    m.angles = vectoangles(dir);
    m.touch = sold_rocket_touch;
    m.nextthink = time + 5;
    m.think = SUB_Remove;
    self.effects = self.effects | EF_MUZZLEFLASH;
};

void() sold_atk1 = [6, sold_atk2] { sigf_say("sigf/soldier_say.wav"); ai_face(); };
void() sold_atk2 = [7, sold_atk3] { ai_face(); };
void() sold_atk3 = [8, sold_atk4] { sold_fire(); };
void() sold_atk4 = [9, sold_run1] { ai_face(); if (random() < 0.4) self.think = sold_atk1; };

void() sold_pain1 = [10, sold_pain2] { };
void() sold_pain2 = [11, sold_run1] { };
void(entity attacker, float damage) sold_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 1;
    sound(self, CHAN_VOICE, "soldier/pain1.wav", 1, ATTN_NORM);
    sold_pain1();
};

void() sold_die1 = [12, sold_die2] { };
void() sold_die2 = [13, sold_die3] { self.solid = SOLID_NOT; };
void() sold_die3 = [14, sold_die4] { };
void() sold_die4 = [15, sold_die5] { };
void() sold_die5 = [16, sold_die5] { };
void() sold_die =
{
    if (self.health < -35)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowHead("progs/gib3.mdl", self.health);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "soldier/death1.wav", 1, ATTN_NORM);
    sold_die1();
};

void() monster_sigf_soldier =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    precache_model("progs/sigf_soldier.mdl");
    precache_model("progs/missile.mdl");
    precache_model("progs/s_explod.spr");
    precache_sound("weapons/sgun1.wav");
    precache_sound("sigf/soldier_say.wav");
    precache_sound("weapons/r_exp3.wav");
    precache_sound("soldier/pain1.wav");
    precache_sound("soldier/death1.wav");
    precache_sound("player/udeath.wav");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_soldier.mdl");
    setsize(self, '-16 -16 -24', '16 16 40');
    self.health = 120;
    self.th_stand = sold_stand1;
    self.th_walk = sold_walk1;
    self.th_run = sold_run1;
    self.th_missile = sold_atk1;
    self.th_pain = sold_pain;
    self.th_die = sold_die;
    walkmonster_start();
    sigf_wear_hat(58);
};

// ---------- the Pyro: a real jet of flame that sets you ablaze ----------
void() pyro_stand1 = [0, pyro_stand2] { ai_stand(); };
void() pyro_stand2 = [1, pyro_stand1] { ai_stand(); };
void() pyro_walk1 = [2, pyro_walk2] { ai_walk(6); };
void() pyro_walk2 = [3, pyro_walk3] { ai_walk(6); };
void() pyro_walk3 = [4, pyro_walk4] { ai_walk(6); };
void() pyro_walk4 = [5, pyro_walk1] { ai_walk(6); };
void() pyro_run1 = [2, pyro_run2] { ai_run(13); };
void() pyro_run2 = [3, pyro_run3] { ai_run(13); };
void() pyro_run3 = [4, pyro_run4] { ai_run(13); };
void() pyro_run4 = [5, pyro_run1] { ai_run(13); };

void() pyro_flame_think =
{
    self.frame = 1 - self.frame;
    sigf_puff(self.origin, 232, 6);
    if (time > self.sigf_until)
    {
        remove(self);
        return;
    }
    self.nextthink = time + 0.07;
};

void() pyro_flame_touch =
{
    if (other == self.owner || other.classname == "sigf_flame")
        return;
    if (other.takedamage)
    {
        if (other.classname == "player")
            T_Damage(other, self, self.owner, 2);
        else
            T_Damage(other, self, self.owner, 4);
        sigf_ignite(other, self.owner);
    }
    remove(self);
};

void() pyro_flame =
{
    local entity f;
    local vector dir;
    ai_face();
    dir = normalize(self.enemy.origin - self.origin);
    f = spawn();
    f.owner = self;
    f.classname = "sigf_flame";
    f.movetype = MOVETYPE_FLYMISSILE;
    f.solid = SOLID_BBOX;
    setmodel(f, "progs/flame2.mdl");
    setsize(f, '-4 -4 -4', '4 4 4');
    setorigin(f, self.origin + dir * 30 + '0 0 6');
    f.velocity = dir * 420 + '0 0 20' + crandom() * '40 40 0';
    f.effects = EF_DIMLIGHT;
    f.touch = pyro_flame_touch;
    f.sigf_until = time + 0.5;
    f.think = pyro_flame_think;
    f.nextthink = time + 0.05;
};

void() pyro_atk1 = [6, pyro_atk2] { sigf_say("sigf/pyro_say.wav"); ai_face(); sound(self, CHAN_WEAPON, "sigf/flame.wav", 1, ATTN_NORM); self.sigf_burst = 0; };
void() pyro_atk2 = [7, pyro_atk3] { pyro_flame(); pyro_flame(); };
void() pyro_atk3 = [8, pyro_atk4] { pyro_flame(); pyro_flame(); };
void() pyro_atk4 = [9, pyro_run1]
{
    pyro_flame();
    pyro_flame();
    self.sigf_burst = self.sigf_burst + 1;
    if (self.sigf_burst < 5)
        self.think = pyro_atk2;
};

void() pyro_pain1 = [10, pyro_pain2] { };
void() pyro_pain2 = [11, pyro_run1] { };
void(entity attacker, float damage) pyro_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 1;
    sound(self, CHAN_VOICE, "player/pain2.wav", 1, ATTN_NORM);
    pyro_pain1();
};

void() pyro_die1 = [12, pyro_die2] { };
void() pyro_die2 = [13, pyro_die3] { self.solid = SOLID_NOT; };
void() pyro_die3 = [14, pyro_die4] { };
void() pyro_die4 = [15, pyro_die5] { };
void() pyro_die5 = [16, pyro_die5] { };
void() pyro_die =
{
    // the fuel tank goes up
    sigf_boom_fx(self.origin + '0 0 20');
    sound(self, CHAN_WEAPON, "weapons/r_exp3.wav", 1, ATTN_NORM);
    sigf_puff(self.origin + '0 0 20', 232, 80);
    T_RadiusDamage(self, self, 25, self);
    if (self.health < -30)
    {
        ThrowHead("progs/gib3.mdl", self.health);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "player/death3.wav", 1, ATTN_NORM);
    pyro_die1();
};

void() monster_sigf_pyro =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    precache_model("progs/sigf_pyro.mdl");
    precache_model("progs/flame2.mdl");
    precache_sound("sigf/flame.wav");
    precache_sound("sigf/pyro_say.wav");
    precache_sound("player/pain2.wav");
    precache_sound("player/death3.wav");
    precache_sound("weapons/r_exp3.wav");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_pyro.mdl");
    setsize(self, '-16 -16 -24', '16 16 40');
    self.health = 120;
    self.th_stand = pyro_stand1;
    self.th_walk = pyro_walk1;
    self.th_run = pyro_run1;
    self.th_missile = pyro_atk1;
    self.th_pain = pyro_pain;
    self.th_die = pyro_die;
    walkmonster_start();
    sigf_wear_hat(56);
};

// ---------- the Engineer's sentry gun: it fights for the player and follows them around ----------
void() sigf_sentry_think =
{
    local entity e, best, p;
    local float bd, d;
    local vector dir, muzzle;

    self.nextthink = time + 0.1;
    p = self.owner;
    if (!p)
    {
        remove(self);
        return;
    }
    if (vlen(p.origin - self.origin) > 450)
    {
        // "teleporter": it pops up again near the player
        makevectors('0 1 0' * p.v_angle_y);
        setorigin(self, p.origin + v_right * 90 - v_forward * 30 + '0 0 6');
        self.velocity = '0 0 0';
        WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
        WriteByte(MSG_BROADCAST, TE_TELEPORT);
        WriteCoord(MSG_BROADCAST, self.origin_x);
        WriteCoord(MSG_BROADCAST, self.origin_y);
        WriteCoord(MSG_BROADCAST, self.origin_z);
        return;
    }
    best = world;
    bd = 1000;
    e = findradius(self.origin, 1000);
    while (e)
    {
        if ((e.flags & FL_MONSTER) && e.health > 0)
        {
            traceline(self.origin + '0 0 12', e.origin, TRUE, self);
            if (trace_fraction == 1)
            {
                d = vlen(e.origin - self.origin);
                if (d < bd)
                {
                    bd = d;
                    best = e;
                }
            }
        }
        e = e.chain;
    }
    if (!best)
    {
        self.angles_y = self.angles_y + 4;
        return;
    }
    dir = normalize(best.origin + '0 0 4' - (self.origin + '0 0 12'));
    self.angles_y = vectoyaw(dir);
    if (time < self.attack_finished)
        return;
    self.attack_finished = time + 0.25;
    muzzle = self.origin + '0 0 12' + dir * 22;
    traceline(muzzle, muzzle + dir * 1200, FALSE, self);
    sound(self, CHAN_WEAPON, "sigf/sentry.wav", 0.8, ATTN_NORM);
    self.effects = self.effects | EF_MUZZLEFLASH;
    particle(muzzle + dir * 60, dir * 30, 192, 4);
    particle(muzzle + dir * 140, dir * 30, 192, 4);
    if (trace_ent.takedamage)
    {
        SpawnBlood(trace_endpos, '0 0 40', 6);
        T_Damage(trace_ent, self, p, 5);
    }
    else
    {
        WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
        WriteByte(MSG_BROADCAST, TE_GUNSHOT);
        WriteCoord(MSG_BROADCAST, trace_endpos_x);
        WriteCoord(MSG_BROADCAST, trace_endpos_y);
        WriteCoord(MSG_BROADCAST, trace_endpos_z);
    }
};

void() SIGF_BuildSentry =
{
    local entity s;
    if (self.sigf_sentry.classname == "sigf_sentry")
        remove(self.sigf_sentry);
    makevectors('0 1 0' * self.v_angle_y);
    s = spawn();
    s.classname = "sigf_sentry";
    s.owner = self;
    s.movetype = MOVETYPE_TOSS;
    s.solid = SOLID_BBOX;
    setmodel(s, "progs/sigf_sentry.mdl");
    setsize(s, '-18 -18 -24', '18 18 32');
    setorigin(s, self.origin + v_forward * 90 + v_right * 36 + '0 0 12');
    s.angles_y = self.v_angle_y;
    s.effects = EF_DIMLIGHT;
    s.think = sigf_sentry_think;
    s.nextthink = time + 0.3;
    self.sigf_sentry = s;
    sound(self, CHAN_ITEM, "sigf/hatpop.wav", 1, ATTN_NORM);
    centerprint(self, "The Engineer built a SENTRY GUN!");
    WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
    WriteByte(MSG_BROADCAST, TE_TELEPORT);
    WriteCoord(MSG_BROADCAST, s.origin_x);
    WriteCoord(MSG_BROADCAST, s.origin_y);
    WriteCoord(MSG_BROADCAST, s.origin_z);
};

// Spawns a monster in the most open direction around the player (a wave must never appear inside a wall), facing the player.
entity(string cls, void() fn, float dist, float side) sigf_spawn_open =
{
    local entity p, e, oself;
    local float i, ang, free, score, best, bestyaw, dd;
    local vector start, org;

    p = self;
    start = p.origin + '0 0 16';
    best = -9999;
    bestyaw = p.v_angle_y;
    for (i = 0; i < 8; i = i + 1)
    {
        // forward first, then the sides, then behind
        ang = floor((i + 1) / 2) * 45;
        if (i & 1)
            ang = 360 - ang;
        if (i == 0)
            ang = 0;
        makevectors('0 1 0' * (p.v_angle_y + ang));
        traceline(start, start + v_forward * 600, TRUE, p);
        free = trace_fraction * 600;
        if (free >= dist + 60 && best < 5000)
        {
            best = 5000;
            bestyaw = p.v_angle_y + ang;
        }
        else if (free > best && best < 5000)
        {
            best = free;
            bestyaw = p.v_angle_y + ang;
        }
    }
    makevectors('0 1 0' * bestyaw);
    traceline(start, start + v_forward * dist, TRUE, p);
    dd = trace_fraction * dist - 50;
    if (dd < 90)
        dd = 90;
    org = start + v_forward * dd;
    traceline(org, org + v_right * side, TRUE, p);
    if (trace_fraction == 1)
        org = org + v_right * side;
    if (pointcontents(org) == CONTENT_SOLID)
        return world;
    e = spawn();
    e.classname = cls;
    setorigin(e, org);
    e.angles_y = vectoyaw(p.origin - org);
    oself = self;
    self = e;
    fn();
    self = oself;
    return e;
};

// ---------- RED respawns: the arena never empties while the demo or a wave is running ----------
void() sigf_respawn_think =
{
    local entity p, e, oself;
    local float alive, r;
    alive = 0;
    e = nextent(world);
    while (e)
    {
        if ((e.flags & FL_MONSTER) && e.health > 0 && e.classname != "monster_sigf_nothing"
            && (e.classname == "monster_sigf_heavy" || e.classname == "monster_sigf_scout" || e.classname == "monster_sigf_soldier" || e.classname == "monster_sigf_pyro"))
            alive = alive + 1;
        e = nextent(e);
    }
    p = find(world, classname, "player");
    remove(self);
    if (!p || alive >= 5)
        return;
    oself = self;
    self = p;
    r = random();
    if (r < 0.25)
        sigf_spawn_open("monster_sigf_scout", monster_sigf_scout, 200, 40);
    else if (r < 0.5)
        sigf_spawn_open("monster_sigf_soldier", monster_sigf_soldier, 230, -40);
    else if (r < 0.75)
        sigf_spawn_open("monster_sigf_pyro", monster_sigf_pyro, 210, 40);
    else
        sigf_spawn_open("monster_sigf_heavy", monster_sigf_heavy, 230, -40);
    self = oself;
};

void() sigf_queue_respawn =
{
    local entity t;
    if (SIGF_Mode() == 0 || SIGF_Mode() == 3)
        return;
    t = spawn();
    t.classname = "sigf_respawn";
    t.think = sigf_respawn_think;
    t.nextthink = time + 1.2;
};

// The first frames of the demo already show the invaders: they are placed in front of the player right after the map starts.
void() sigf_opening_think =
{
    local entity p, oself;
    p = find(world, classname, "player");
    if (!p)
    {
        self.nextthink = time + 0.15;
        return;
    }
    oself = self;
    self = p;
    sigf_spawn_open("monster_sigf_heavy", monster_sigf_heavy, 190, -30);
    sigf_spawn_open("monster_sigf_scout", monster_sigf_scout, 170, 50);
    self = oself;
    remove(self);
};

// ---------- the three hooks ----------
void() SIGF_Precache =
{
    precache_model("progs/sigf_hat.mdl");
    precache_model("progs/sigf_hathead.mdl");
    precache_model("progs/sigf_sentry.mdl");
    precache_model("progs/sigf_sandvich.spr");
    precache_model("progs/flame2.mdl");
    precache_sound("sigf/crit.wav");
    precache_sound("sigf/fanfare.wav");
    precache_sound("sigf/hatpop.wav");
    precache_sound("sigf/munch.wav");
    precache_sound("sigf/sentry.wav");
    if (SIGF_Mode() == 1 || SIGF_Mode() == 2)
    {
        local entity o;
        o = spawn();
        o.classname = "sigf_opening";
        o.think = sigf_opening_think;
        o.nextthink = time + 0.5;
    }
    SIGF_Preload("monster_sigf_heavy", monster_sigf_heavy);
    SIGF_Preload("monster_sigf_scout", monster_sigf_scout);
    SIGF_Preload("monster_sigf_soldier", monster_sigf_soldier);
    SIGF_Preload("monster_sigf_pyro", monster_sigf_pyro);
};

void(float wave) SIGF_DemoWave =
{
    local float k;
    if (wave == 0)
    {
        self.items = self.items | IT_SHOTGUN | IT_SUPER_SHOTGUN | IT_NAILGUN | IT_SUPER_NAILGUN | IT_ROCKET_LAUNCHER;
        self.weapon = IT_ROCKET_LAUNCHER;
        W_SetCurrentAmmo();
        centerprint(self, "RED TEAM has taken over Quake!");
        SIGF_BuildSentry();
        sigf_spawn_open("monster_sigf_heavy", monster_sigf_heavy, 200, -70);
        sigf_spawn_open("monster_sigf_scout", monster_sigf_scout, 190, 60);
        sigf_spawn_open("monster_sigf_soldier", monster_sigf_soldier, 230, 130);
        return;
    }
    k = wave - floor(wave / 3) * 3;
    if (k == 0)
        self.weapon = IT_ROCKET_LAUNCHER;
    else if (k == 1)
        self.weapon = IT_SHOTGUN;
    else
        self.weapon = IT_NAILGUN;
    W_SetCurrentAmmo();
    k = wave - floor(wave / 4) * 4;
    if (k == 0)
    {
        sigf_spawn_open("monster_sigf_pyro", monster_sigf_pyro, 210, 0);
        sigf_spawn_open("monster_sigf_scout", monster_sigf_scout, 200, 90);
        sigf_spawn_open("monster_sigf_soldier", monster_sigf_soldier, 230, -90);
    }
    else if (k == 1)
    {
        sigf_spawn_open("monster_sigf_heavy", monster_sigf_heavy, 200, 40);
        sigf_spawn_open("monster_sigf_scout", monster_sigf_scout, 190, -90);
    }
    else if (k == 2)
    {
        sigf_spawn_open("monster_sigf_soldier", monster_sigf_soldier, 230, 0);
        sigf_spawn_open("monster_sigf_pyro", monster_sigf_pyro, 210, -80);
        sigf_spawn_open("monster_sigf_scout", monster_sigf_scout, 190, 80);
    }
    else
    {
        sigf_spawn_open("monster_sigf_heavy", monster_sigf_heavy, 230, 50);
        sigf_spawn_open("monster_sigf_pyro", monster_sigf_pyro, 200, -50);
        sigf_spawn_open("monster_sigf_soldier", monster_sigf_soldier, 210, 120);
    }
};

void(entity targ, entity attacker) SIGF_OnKilled =
{
    if (!(targ.flags & FL_MONSTER))
        return;
    sigf_drop_hat(targ.origin);
    sigf_queue_respawn();
    if (targ.classname == "monster_sigf_heavy" || random() < 0.15)
        sigf_drop_sandvich(targ.origin);
    if (attacker.classname == "player")
    {
        centerprint(attacker, "RED ", sigf_name(targ), " DOWN!\nYou are a menace.");
        sprint(attacker, "You killed the RED ");
        sprint(attacker, sigf_name(targ));
        sprint(attacker, "!\n");
        if (time - attacker.sigf_last_kill < 8)
            attacker.sigf_streak = attacker.sigf_streak + 1;
        else
            attacker.sigf_streak = 1;
        attacker.sigf_last_kill = time;
        if (attacker.sigf_streak == 3)
        {
            centerprint(attacker, "DOMINATION!\nThree kills in a row");
            sound(attacker, CHAN_VOICE, "sigf/fanfare.wav", 1, ATTN_NONE);
        }
        if (attacker.sigf_streak == 6)
            centerprint(attacker, "REVENGE! RED TEAM IS CRYING");
    }
};
