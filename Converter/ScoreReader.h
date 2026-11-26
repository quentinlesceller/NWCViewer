#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// -1: unrecognized header; 0: converted; 1: invalid or unsupported score.
int ConvertNWCScore(const char* input, const char* output);
#ifdef __cplusplus
}
#endif
