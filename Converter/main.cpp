#include "ScoreReader.h"
#include <cstdio>
#include <string>
int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  std::string input(argv[1]);
  auto dot = input.find_last_of('.');
  if (dot == std::string::npos || input.substr(dot) != ".nwc")
    return 2;
  return ConvertNWCScore(input.c_str(),
                         (input.substr(0, dot) + ".xml").c_str()) == 0
             ? 0
             : 1;
}
