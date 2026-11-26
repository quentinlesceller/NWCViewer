#pragma once
#include <map>
#include <string>
#include <vector>

namespace score {
using std::string;
struct Record {
  string kind;
  std::map<string, string> fields;
  string get(const string &key, const string &def = "") const {
    auto i = fields.find(key);
    return i == fields.end() ? def : i->second;
  }
};
struct Syllable {
  string text, kind;
};
struct Staff {
  string name, abbreviation;
  bool visible = true;
  bool legacyAccidentals = false;
  int transpose = 0;
  std::vector<Record> events;
  std::map<int, std::vector<Syllable>> lyrics;
};
struct Score {
  Record info;
  std::vector<Staff> staves;
};
Score readLegacy(const string &data, unsigned version);
} // namespace score
