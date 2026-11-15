#pragma once
// -1: legacy/other format; 0: converted; 1: invalid/unsupported modern score.
int ConvertModernNWC(const char* input, const char* output);
