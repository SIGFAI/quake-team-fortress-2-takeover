// SIGF kit (frozen, restored by check.ps1 before every compile): the demo player and the wave clock.
// Quake has no bots: in demo mode (cvar scratch1 = 1, set by play.ps1 -Demo; 2 = intermission waves) the
// real player is steered from QuakeC. Every frame it aims at the closest visible monster, keeps a readable
// distance, strafes, fires, and explores when nothing is in sight. It is invincible (god mode) and never
// runs out of ammo. With scratch1 = 0 (normal play) the pilot does nothing.
// The wave clock calls the mod's SIGF_DemoWave(n) (self = the player): wave 0 after 1.5 s, then every 8 s
// (intermission: every 25 s, at most 14 monsters alive).
// scratch1 = 3: headless check (dedicated server, no player, check.ps1 -Headless). A stand-in entity at the
// map start takes the player's place for the waves (every 4 s), and every monster is killed 2.5 s after each
// wave (by turns a normal death and a gib death), so spawn, pain, death and SIGF_OnKilled code all run.

float SIGF_TURN_SPEED = 200;   // degrees per second: faster is unreadable on stream
float SIGF_NEAR = 220;         // backs off below this distance (the monster would fill the screen)
float SIGF_FAR = 650;          // walks in above it
float SIGF_RUN = 300;          // walking speed (the player's max is 320)

float sigf_wave;
float sigf_next_wave;
float sigf_ready_said;
float sigf_kill_at;
float sigf_kills;
entity sigf_stand_in;

.float sigf_scan_at;
.entity sigf_target;
.float sigf_target_dist;
.entity sigf_heard;            // closest monster not in sight: walked toward when nothing is visible
.float sigf_goal_yaw;          // explore direction
.float sigf_strafe_until;
.float sigf_strafe_dir;
.float sigf_stuck_at;          // last wall bump or stuck turn
.float sigf_check_at;          // next progress check
.vector sigf_last_pos;
.float sigf_ammo_at;

float() SIGF_Mode = { return cvar("scratch1"); };

// The player, or in a headless check the stand-in at the map start (world if neither exists yet).
entity() SIGF_Anchor =
{
    local entity p, spot;
    p = find(world, classname, "player");
    if (p || SIGF_Mode() != 3)
        return p;
    if (!sigf_stand_in)
    {
        spot = find(world, classname, "info_player_start");
        if (!spot)
            return world;
        sigf_stand_in = spawn();
        sigf_stand_in.classname = "sigf_stand_in";
        setorigin(sigf_stand_in, spot.origin);
        sigf_stand_in.v_angle = spot.angles;
        sigf_stand_in.health = 100;
        sigf_stand_in.max_health = 100;
    }
    return sigf_stand_in;
};

// Headless check: every living monster dies (normal death on even sweeps, gibs on odd ones).
void() SIGF_KillAll =
{
    local entity m;
    m = nextent(world);
    while (m)
    {
        if ((m.flags & FL_MONSTER) && m.health > 0)
        {
            if (sigf_kills & 1)
                T_Damage(m, world, world, m.health + 200);
            else
                T_Damage(m, world, world, m.health + 1);
        }
        m = nextent(m);
    }
    sigf_kills = sigf_kills + 1;
    dprint("SIGF_KILLALL\n");
};

float() SIGF_CountMonsters =
{
    local entity m;
    local float n;
    n = 0;
    m = nextent(world);
    while (m)
    {
        if ((m.flags & FL_MONSTER) && m.health > 0)
            n = n + 1;
        m = nextent(m);
    }
    return n;
};

entity(string cls, void() spawnfunc, float dist, float side) SIGF_SpawnAhead =
{
    local entity p, e, oself;
    local vector start, org;

    p = SIGF_Anchor();
    if (!p)
        return world;
    makevectors('0 1 0' * p.v_angle_y);
    start = p.origin + '0 0 16';
    org = start + v_forward * dist + v_right * side;
    traceline(start, org, TRUE, p);
    org = trace_endpos - v_forward * 48;   // keep off the wall it hit
    if (pointcontents(org) == CONTENT_SOLID)
        return world;
    e = spawn();
    e.classname = cls;
    setorigin(e, org);
    e.angles_y = p.v_angle_y + 180;          // faces the player
    oself = self;
    self = e;
    spawnfunc();
    self = oself;
    return e;
};

void(string cls, void() spawnfunc) SIGF_Preload =
{
    local entity e, oself;
    local float tm;

    tm = total_monsters;
    e = spawn();
    e.classname = cls;
    oself = self;
    self = e;
    spawnfunc();
    self = oself;
    remove(e);
    total_monsters = tm;
};

void() SIGF_StartFrame =
{
    local entity p, oself;

    sigf_started = TRUE;
    if (SIGF_Mode() == 0)
        return;
    p = SIGF_Anchor();
    if (!p)
        return;
    if (SIGF_Mode() == 3 && sigf_kill_at && time > sigf_kill_at)
    {
        sigf_kill_at = 0;
        SIGF_KillAll();
    }
    if (!sigf_ready_said)
    {
        sigf_ready_said = TRUE;
        sigf_next_wave = time + 1.5;
        dprint("SIGF_READY\n");
    }
    if (time < sigf_next_wave)
        return;
    if (SIGF_Mode() == 2 && SIGF_CountMonsters() >= 14)
    {
        sigf_next_wave = time + 5;
        return;
    }
    oself = self;
    self = p;
    SIGF_DemoWave(sigf_wave);
    self = oself;
    dprint("SIGF_WAVE ");
    dprint(ftos(sigf_wave));
    dprint("\n");
    sigf_wave = sigf_wave + 1;
    if (SIGF_Mode() == 2)
        sigf_next_wave = time + 25;
    else if (SIGF_Mode() == 3)
    {
        sigf_next_wave = time + 4;
        sigf_kill_at = time + 2.5;
    }
    else
        sigf_next_wave = time + 8;
};

// Closest visible living monster (and the closest one out of sight), refreshed every 0.15 s.
void() SIGF_PilotScan =
{
    local entity m;
    local float d, best, heard;
    local vector eye;

    self.sigf_target = world;
    self.sigf_heard = world;
    best = 3000;
    heard = 3000;
    eye = self.origin + self.view_ofs;
    m = nextent(world);
    while (m)
    {
        if ((m.flags & FL_MONSTER) && m.health > 0)
        {
            d = vlen(m.origin - self.origin);
            if (d < best || d < heard)
            {
                traceline(eye, (m.absmin + m.absmax) * 0.5, TRUE, self);
                if (trace_fraction == 1)
                {
                    if (d < best) { best = d; self.sigf_target = m; }
                }
                else if (d < heard) { heard = d; self.sigf_heard = m; }
            }
        }
        m = nextent(m);
    }
    self.sigf_target_dist = best;
};

void() SIGF_PilotThink =
{
    local vector dir, ang, wish, v;
    local float goal, pitch, diff, step, aimed;

    if (SIGF_Mode() == 0)
        return;
    self.button0 = 0;
    if (self.health <= 0)
        return;
    self.flags = self.flags | FL_GODMODE;

    // Never out of ammo.
    if (time > self.sigf_ammo_at)
    {
        self.sigf_ammo_at = time + 1;
        if (self.ammo_shells < 25 || self.ammo_nails < 50 || self.ammo_rockets < 10 || self.ammo_cells < 25)
        {
            if (self.ammo_shells < 50) self.ammo_shells = 50;
            if (self.ammo_nails < 150) self.ammo_nails = 150;
            if (self.ammo_rockets < 25) self.ammo_rockets = 25;
            if (self.ammo_cells < 50) self.ammo_cells = 50;
            W_SetCurrentAmmo();
        }
    }

    if (time > self.sigf_scan_at)
    {
        self.sigf_scan_at = time + 0.15;
        SIGF_PilotScan();
    }
    if (self.sigf_target && self.sigf_target.health <= 0)
        self.sigf_target = world;

    pitch = 0;
    if (self.sigf_target)
    {
        dir = (self.sigf_target.absmin + self.sigf_target.absmax) * 0.5 - (self.origin + self.view_ofs);
        ang = vectoangles(dir);
        goal = ang_y;
        pitch = ang_x;
        if (pitch > 180)
            pitch = pitch - 360;
        pitch = 0 - pitch;               // v_angle: positive pitch looks down
        if (pitch > 40) pitch = 40;
        if (pitch < -40) pitch = -40;
    }
    else if (self.sigf_heard)
    {
        ang = vectoangles(self.sigf_heard.origin - self.origin);
        goal = ang_y;
        if (time < self.sigf_stuck_at + 2)  // just bumped a wall: follow the explore direction a moment
            goal = self.sigf_goal_yaw;
    }
    else
        goal = self.sigf_goal_yaw;

    // Turn toward the goal at a readable speed.
    diff = anglemod(goal - self.v_angle_y);
    if (diff > 180)
        diff = diff - 360;
    aimed = fabs(diff) < 12;
    step = SIGF_TURN_SPEED * frametime;
    if (diff > step) diff = step;
    if (diff < 0 - step) diff = 0 - step;
    self.v_angle_y = anglemod(self.v_angle_y + diff);
    self.v_angle_x = self.v_angle_x + (pitch - self.v_angle_x) * 0.2;
    self.v_angle_z = 0;
    self.angles_y = self.v_angle_y;
    self.angles_x = 0 - self.v_angle_x / 3;
    self.fixangle = TRUE;

    makevectors('0 1 0' * self.v_angle_y);
    wish = '0 0 0';
    if (self.sigf_target)
    {
        if (self.sigf_target_dist > SIGF_FAR)
            wish = v_forward;
        else if (self.sigf_target_dist < SIGF_NEAR)
            wish = 0 - v_forward;
        if (time > self.sigf_strafe_until)
        {
            self.sigf_strafe_until = time + 0.8 + random() * 1.4;
            self.sigf_strafe_dir = 0;
            if (random() < 0.7)
            {
                if (random() < 0.5) self.sigf_strafe_dir = 1;
                else self.sigf_strafe_dir = -1;
            }
        }
        wish = wish + v_right * self.sigf_strafe_dir * 0.7;
        if (aimed)
            self.button0 = 1;
    }
    else
        wish = v_forward;

    // Walls: a strafe into a wall flips, a walk into a wall turns the explore direction.
    if (wish != '0 0 0')
    {
        traceline(self.origin, self.origin + normalize(wish) * 56, TRUE, self);
        if (trace_fraction < 1)
        {
            if (self.sigf_target)
                self.sigf_strafe_dir = 0 - self.sigf_strafe_dir;
            else
            {
                self.sigf_goal_yaw = anglemod(self.v_angle_y + 90 + random() * 180);
                self.sigf_stuck_at = time;
            }
        }
    }
    // Stuck (no progress in 1 s): turn away.
    if (time > self.sigf_check_at)
    {
        self.sigf_check_at = time + 1;
        if (wish != '0 0 0' && vlen(self.origin - self.sigf_last_pos) < 24)
        {
            self.sigf_goal_yaw = anglemod(self.v_angle_y + 120 + random() * 120);
            self.sigf_stuck_at = time;
        }
        self.sigf_last_pos = self.origin;
    }

    if ((self.flags & FL_ONGROUND) && wish != '0 0 0')
    {
        v = normalize(wish) * SIGF_RUN;
        self.velocity_x = v_x;
        self.velocity_y = v_y;
    }
};
