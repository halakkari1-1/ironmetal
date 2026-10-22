// Offline recorder for engine-sim (AngeTheGreat, MIT): loads an engine script, starts the engine, then holds it
// on the dynamometer at fixed RPMs with the throttle open (on load) and closed (off load), and writes each
// steady state to a WAV file. These become the engine loops for IronMetal's cars.
//
// usage: recorder <engine.mr> <outdir> <rpm list comma separated> [seconds]
#include "es-src/scripting/include/engine_sim.h"
#include "es-src/scripting/include/compiler.h"
#include "es-src/include/units.h"

#include <cstdio>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <iostream>

static bool readWav(const std::string &path, std::vector<int16_t> &out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    std::vector<char> d((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    size_t i = 12;
    int channels = 1, bits = 16;
    while (i + 8 <= d.size()) {
        std::string id(&d[i], 4);
        uint32_t sz = *(uint32_t *)&d[i + 4];
        if (id == "fmt ") { channels = *(uint16_t *)&d[i + 10]; bits = *(uint16_t *)&d[i + 22]; }
        if (id == "data") {
            if (bits != 16) return false;
            const int16_t *s = (const int16_t *)&d[i + 8];
            size_t n = sz / 2 / channels;
            out.resize(n);
            for (size_t k = 0; k < n; ++k) out[k] = s[k * channels];
            return true;
        }
        i += 8 + sz + (sz & 1);
    }
    return false;
}

static void writeWav(const std::string &path, const std::vector<int16_t> &s) {
    std::ofstream f(path, std::ios::binary);
    uint32_t rate = 44100, bytes = s.size() * 2;
    auto w32 = [&](uint32_t v) { f.write((char *)&v, 4); };
    auto w16 = [&](uint16_t v) { f.write((char *)&v, 2); };
    f.write("RIFF", 4); w32(36 + bytes); f.write("WAVE", 4);
    f.write("fmt ", 4); w32(16); w16(1); w16(1); w32(rate); w32(rate * 2); w16(2); w16(16);
    f.write("data", 4); w32(bytes);
    f.write((const char *)s.data(), bytes);
}

struct Rig {
    Simulator *sim = nullptr;
    Engine *engine = nullptr;
    std::vector<int16_t> out;
    double speed = 0;

    // one 1/120 s frame of simulation and audio
    void frame(bool keep) {
        sim->startFrame(1.0 / 120.0);
        while (sim->simulateStep()) {}
        sim->synthesizer().renderAudio();
        sim->endFrame();
        int16_t buf[4096];
        int n = sim->readAudioOutput(4096, buf);
        if (keep) out.insert(out.end(), buf, buf + n);
    }

    void run(double seconds, bool keep) {
        int frames = (int)(seconds * 120);
        for (int i = 0; i < frames; ++i) {
            // the throttle follows the setting smoothly, as in the app
            engine->setSpeedControl(speed);
            frame(keep);
        }
    }
};

int main(int argc, char **argv) {
    if (argc < 4) { std::cerr << "usage: recorder engine.mr outdir rpms [seconds]\n"; return 1; }
    std::string script = argv[1], outdir = argv[2];
    std::vector<int> rpms;
    { std::stringstream ss(argv[3]); std::string t; while (std::getline(ss, t, ',')) rpms.push_back(std::stoi(t)); }
    double secs = argc > 4 ? std::stod(argv[4]) : 3.0;

    // a main script that imports the engine and runs it
    {
        std::ofstream m("__main.mr");
        m << "import \"engine_sim.mr\"\nimport \"" << script << "\"\nmain()\n";
    }
    es_script::Compiler compiler;
    compiler.initialize();
    if (!compiler.compile("__main.mr")) { std::cerr << "compile failed (see error_log.log)\n"; return 2; }
    es_script::Compiler::Output o = compiler.execute();
    compiler.destroy();
    if (!o.engine) { std::cerr << "no engine\n"; return 3; }

    Vehicle *vehicle = o.vehicle;
    Transmission *transmission = o.transmission;
    if (!vehicle) {
        Vehicle::Parameters vp;
        vp.mass = units::mass(1597, units::kg); vp.diffRatio = 3.42; vp.tireRadius = units::distance(10, units::inch);
        vp.dragCoefficient = 0.25; vp.crossSectionArea = units::distance(6.0, units::foot) * units::distance(6.0, units::foot);
        vp.rollingResistance = 2000.0;
        vehicle = new Vehicle; vehicle->initialize(vp);
    }
    if (!transmission) {
        static const double gr[] = {2.97, 2.07, 1.43, 1.00, 0.84, 0.56};
        Transmission::Parameters tp; tp.GearCount = 6; tp.GearRatios = gr; tp.MaxClutchTorque = units::torque(1000.0, units::ft_lb);
        transmission = new Transmission; transmission->initialize(tp);
    }

    Engine *engine = o.engine;
    engine->calculateDisplacement();
    Simulator *sim = engine->createSimulator(vehicle, transmission);
    sim->setSimulationFrequency(engine->getSimulationFrequency());
    sim->synthesizer().m_run = false;   // no audio thread: frames render synchronously
    Synthesizer::AudioParameters ap = sim->synthesizer().getAudioParameters();
    ap.inputSampleNoise = (float)engine->getInitialJitter();
    ap.airNoise = (float)engine->getInitialNoise();
    ap.dF_F_mix = (float)engine->getInitialHighFrequencyGain();
    // a fixed gain instead of the automatic leveller: keeps on-load louder than off-load and never clips
    const char *g = getenv("ES_GAIN");
    ap.levelerMinGain = ap.levelerMaxGain = g ? (float)atof(g) : 1.0f;
    sim->synthesizer().setAudioParameters(ap);
    sim->synthesizer().m_levelingFilter.p_minLevel = ap.levelerMinGain;
    sim->synthesizer().m_levelingFilter.p_maxLevel = ap.levelerMaxGain;
    for (int i = 0; i < engine->getExhaustSystemCount(); ++i) {
        ImpulseResponse *r = engine->getExhaustSystem(i)->getImpulseResponse();
        std::vector<int16_t> ir;
        if (!readWav(r->getFilename(), ir)) { std::cerr << "impulse response missing: " << r->getFilename() << "\n"; return 4; }
        sim->synthesizer().initializeImpulseResponse(ir.data(), ir.size(), r->getVolume(), i);
    }

    Rig rig; rig.sim = sim; rig.engine = engine;
    std::cerr << "engine: " << engine->getName() << " redline " << units::toRpm(engine->getRedline()) << "\n";

    // start: ignition on, starter until it runs on its own
    engine->getIgnitionModule()->m_enabled = true;
    // crank with a little throttle until it fires and holds idle on its own (big engines take a while)
    for (int attempt = 0; attempt < 4 && engine->getRpm() < 300; ++attempt) {
        sim->m_starterMotor.m_enabled = true;
        rig.speed = 0.2;
        rig.run(2.0, false);
        sim->m_starterMotor.m_enabled = false;
        rig.speed = 0.0;
        rig.run(2.0, false);
        std::cerr << "start attempt " << attempt << " rpm " << engine->getRpm() << "\n";
    }
    std::cerr << "idle rpm " << engine->getRpm() << "\n";

    // idle loop
    rig.out.clear();
    rig.run(secs, true);
    writeWav(outdir + "/idle.wav", rig.out);

    for (int r : rpms) {
        for (int on = 1; on >= 0; --on) {
            sim->m_dyno.m_enabled = true;
            sim->m_dyno.m_hold = true;
            sim->m_dyno.m_rotationSpeed = units::rpm(r);
            rig.speed = on ? 1.0 : 0.0;
            rig.run(1.5, false);
            rig.out.clear();
            rig.run(secs, true);
            char name[256];
            std::snprintf(name, sizeof name, "%s/%05d_%s.wav", outdir.c_str(), r, on ? "on" : "off");
            writeWav(name, rig.out);
            std::cerr << name << " rpm " << engine->getRpm() << " samples " << rig.out.size() << "\n";
        }
    }
    return 0;
}
