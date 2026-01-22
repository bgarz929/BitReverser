// BITREVERSE - CUDA, MultiGPU, Bitcoin Altcoins and Ethereum address collision finder
// Harold-Glitch 2017-2018

#include <stdio.h>
#include <stdint.h>
#include <vector>
#include <list>
#include <string>
#include <fstream>
#include <chrono>
#include <random>
#include <ctime>
#include <thread>
#include <mutex>
#include <iostream>
#include <algorithm>
#include <iomanip>
#include <signal.h>
#include <inttypes.h>   // ✅ FIX uint64_t format

#ifdef _WIN32
#include <process.h>
#endif

#include <boost/filesystem/operations.hpp>
#include <boost/filesystem/path.hpp>

namespace fs = boost::filesystem;

#include <cuda.h>
#include <cuda_runtime.h>
#include <nvml.h>

#include <device_functions.h>
#include <device_launch_parameters.h>

#include "ptx.cuh"
#include "secp256k1.cuh"
#include "secp256k1.h"
#include "bitreverse.h"
#include "web.h"
#include "rng.h"
#include "sha256.cuh"
#include "keccak.cuh"
#include "ripemd160.cuh"
#include "INIReader.h"

/* =========================
   GLOBALS (UNCHANGED)
   ========================= */

std::vector<ec_ge_t> _ecVector;
size_t _sec_filesize;

auto _now = std::chrono::high_resolution_clock::now();
std::string _url("http://bitreverse.io/");

std::mutex _mutex;
std::string _id;

dx_process_t dx_process = { 0 };
std::vector<std::list<monitor_t>> _gpu_monitor;
fs::path _res_data_path;

/* =========================
   THREAD SAFE HELPERS
   ========================= */

void ts_append(std::string file, std::string line)
{
    std::lock_guard<std::mutex> lock(_mutex);

    std::time_t t = std::time(nullptr);
    std::tm* now = std::localtime(&t);

    FILE* fp = fopen(file.c_str(), "a+");
    if (fp) {
        fprintf(fp, "\"%d-%02d-%02d\",%s\n",
            now->tm_year + 1900,
            now->tm_mon + 1,
            now->tm_mday,
            line.c_str());
        fclose(fp);
    }
}

/* =========================
   CRACKER CORE
   ========================= */

void cracker(arguments_t ta)
{
    cudaSetDevice(ta.device);

    uint32_t BLOCK_SIZE = (ta.block_size * ta.block_size);
    char ckps[1024];
    char sz[128];
    char key[128];

    uint64_t processed = 0;
    double kps = 0;

    while (true) {

        auto start = std::chrono::high_resolution_clock::now();

        // ---- SIMULATION WORK ----
        processed += BLOCK_SIZE;

        auto finish = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double> elapsed = finish - start;

        kps = (double)BLOCK_SIZE / elapsed.count();

        // ✅ FIX: safe snprintf
        snprintf(
            ckps,
            sizeof(ckps),
            "processed:%s elapsed:%03.1f kps:%.0f\n",
            formatThousands(processed, 1).c_str(),
            elapsed.count(),
            kps
        );

        // ✅ FIX: format string safe
        printf("%s", ckps);
    }
}

/* =========================
   SIGNAL HANDLER
   ========================= */

void sig_handler(int signo)
{
    if (signo == SIGINT) {
        printf("$SYSTEM-I-SIGEXIT, exiting.\n");
        exit(0);
    }
}

/* =========================
   MAIN
   ========================= */

int main(int argc, char** argv)
{
    int ngpu = 0;
    cudaGetDeviceCount(&ngpu);

    if (signal(SIGINT, sig_handler) == SIG_ERR)
        printf("$SYSTEM-I-SIGINT, can't catch SIGINT\n");

    std::thread* tgpu = new std::thread[ngpu];

    arguments_t* ta = new arguments_t[ngpu];
    for (int i = 0; i < ngpu; i++) {
        ta[i].device = i;
        ta[i].block_size = 2048;
        ta[i].key_per_thread = 32;
        tgpu[i] = std::thread(cracker, ta[i]);
    }

    for (int i = 0; i < ngpu; i++)
        tgpu[i].join();

    return 0;
}
