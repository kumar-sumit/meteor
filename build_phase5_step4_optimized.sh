#!/bin/bash
g++ -std=c++17 -o meteor_phase5_step4 sharded_server_phase5_step4_optimized.cpp -pthread -O3 -lboost_fiber -lboost_context -levent -lssl -lcrypto -lz -lpcre -luring -lnuma -I.
