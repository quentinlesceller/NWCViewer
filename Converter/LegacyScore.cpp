#include "ScoreData.h"
#include <algorithm>
#include <array>
#include <codecvt>
#include <cstdint>
#include <locale>
#include <stdexcept>

namespace score {
namespace {
// All lengths and offsets below refer to the decompressed little-endian wire
// format.
class Cursor {
  const string &bytes;

public:
  size_t pos, end;
  Cursor(const string &data, size_t start, size_t limit)
      : bytes(data), pos(start), end(limit) {}
  size_t take(size_t n) {
    if (n > end - pos)
      throw std::runtime_error("Truncated legacy score");
    size_t at = pos;
    pos += n;
    return at;
  }
  int peek() const { return static_cast<unsigned char>(bytes.at(pos)); }
  int byte() { return static_cast<unsigned char>(bytes[take(1)]); }
  int word() {
    int low = byte();
    return low + 256 * byte();
  }
  Cursor block(size_t n) {
    size_t at = take(n);
    return Cursor(bytes, at, pos);
  }
  string text() {
    const size_t begin = pos;
    while (pos < end && bytes[pos])
      ++pos;
    size_t length = pos - begin;
    take(1);
    if (length > 1024 * 1024)
      throw std::runtime_error("Text field too large");
    const char *first = bytes.data() + begin;
    std::wstring_convert<std::codecvt_utf8<char32_t>, char32_t> utf8;
    try {
      utf8.from_bytes(first, first + length);
      if (utf8.converted() == length)
        return string(first, length);
    } catch (const std::range_error &) { /* Try the legacy encoding below. */
    }
    // Old Windows scores store metadata and lyrics in Windows-1252.
    static const int extended[] = {
        8364, 65533, 8218,  402,  8222,  8230,  8224, 8225,  710,  8240, 352,
        8249, 338,   65533, 381,  65533, 65533, 8216, 8217,  8220, 8221, 8226,
        8211, 8212,  732,   8482, 353,   8250,  339,  65533, 382,  376};
    string out;
    for (size_t i = begin; i < begin + length; ++i) {
      int c = static_cast<unsigned char>(bytes[i]);
      if (c >= 128 && c < 160)
        c = extended[c - 128];
      if (c < 128)
        out += char(c);
      else {
        if (c >= 2048) {
          out += char(224 | (c >> 12));
          out += char(128 | ((c >> 6) & 63));
        } else
          out += char(192 | (c >> 6));
        out += char(128 | (c & 63));
      }
    }
    return out;
  }
};

const char *choice(std::initializer_list<const char *> values, int index) {
  if (index < 0 || size_t(index) >= values.size())
    throw std::runtime_error("Unsupported notation value");
  return values.begin()[index];
}

struct Tone {
  Record event;
  int ticks;
};
Tone tone(Cursor &c, unsigned version, bool rest) {
  int exponent = c.byte() & 15;
  string duration =
      choice({"Whole", "Half", "4th", "8th", "16th", "32nd", "64th"}, exponent);
  c.take(1);
  int flags = c.byte();
  int lyricFlags = c.byte();
  int accents = c.byte(), articulation = c.byte();
  int ticks = 1920 >> exponent;
  if (accents & 1) {
    duration += ",DblDotted";
    ticks = ticks * 7 / 4;
  } else if (accents & 4) {
    duration += ",Dotted";
    ticks = ticks * 3 / 2;
  }
  if (flags & 12) {
    duration += choice({"", ",Triplet=First", ",Triplet", ",Triplet=End"},
                       (flags >> 2) & 3);
    ticks = ticks * 2 / 3;
  }
  Record r;
  r.kind = rest ? "Rest" : "Note";
  if (rest) {
    if (version > 0x132)
      c.take(2);
  } else {
    int position = -static_cast<int8_t>(c.byte());
    int accidental = c.byte();
    if (version <= 0x146)
      c.take(2);
    if (version >= 0x200 && (accidental & 64))
      c.take(1);
    string pitch =
        choice({"#", "b", "n", "x", "v", "", "", ""}, accidental & 7);
    r.fields["Pos"] =
        pitch + std::to_string(position) + ((accents & 16) ? "^" : "");
    if (accents & 2)
      duration += ",Staccato";
    if (accents & 32)
      duration += ",Accent";
    if (articulation & 4)
      duration += ",Tenuto";
    if ((articulation & 3) == 1 || (articulation & 3) == 3)
      duration += ",Slur";
    if (articulation & 32) {
      duration += ",Grace";
      ticks = 0;
    }
    string opts = choice({"", "Stem=Up", "Stem=Down", ""}, (flags >> 4) & 3);
    if (flags & 3)
      opts += choice({"", ",Beam=First", ",Beam=End", ",Beam"}, flags & 3);
    if (lyricFlags & 1)
      opts += ",Lyric=Never";
    else if (flags & 128)
      opts += ",Lyric=Always";
    r.fields["Opts"] = opts;
  }
  r.fields["Dur"] = duration;
  return {r, ticks};
}

void chord(Cursor &c, unsigned version, Staff &staff, bool hasRest) {
  std::vector<Tone> tones;
  if (hasRest)
    tones.push_back(tone(c, version, true));
  else {
    Cursor header = c.block(version <= 0x146 ? 12 : 8);
    header.take(7);
    if ((header.byte() & 64) && version >= 0x200)
      c.take(1);
  }
  int count = c.word();
  if (count < 1 || count > 64)
    throw std::runtime_error("Invalid chord size");
  for (int i = 0; i < count; ++i) {
    int type = c.word();
    if (version >= 0x146)
      c.take(1);
    if (type != 8 && type != 9)
      throw std::runtime_error("Unsupported chord member");
    tones.push_back(tone(c, version, type == 9));
  }
  // Advance by the shortest member. Longer notes continue in a separate voice.
  std::stable_sort(
      tones.begin(), tones.end(),
      [](const Tone &a, const Tone &b) { return a.ticks > b.ticks; });
  bool split = tones.front().ticks != tones.back().ticks;
  for (size_t i = 0; i < tones.size();) {
    Tone group = tones[i++];
    while (i < tones.size() && group.ticks == tones[i].ticks &&
           group.event.kind != "Rest" && tones[i].event.kind != "Rest") {
      group.event.kind = "Chord";
      group.event.fields["Pos"] += "," + tones[i++].event.get("Pos");
    }
    if (split)
      group.event.fields["Voice"] =
          group.event.get("Opts").find("Stem=Down") != string::npos ? "2" : "1";
    staff.events.push_back(std::move(group.event));
    if (i < tones.size() && group.ticks)
      staff.events.push_back(
          {"Rewind", {{"Ticks", std::to_string(group.ticks)}}});
  }
}

Record event(Cursor &c, unsigned version, int type) {
  Record r;
  switch (type) {
  case 0: {
    r.kind = "Clef";
    r.fields["Type"] = choice({"Treble", "Bass", "Alto", "Tenor"}, c.word());
    r.fields["OctaveShift"] =
        choice({"", "Octave Up", "Octave Down"}, c.word());
    break;
  }
  case 1: {
    int flats = c.byte();
    c.take(1);
    int sharps = c.byte();
    c.take(7);
    string signature;
    for (int i = 0; i < 7; ++i)
      if ((flats | sharps) & (1 << i)) {
        if (!signature.empty())
          signature += ",";
        signature += char('A' + i);
        signature += (flats & (1 << i)) ? 'b' : '#';
      }
    return {"Key", {{"Signature", signature}}};
  }
  case 2: {
    int style = c.byte() & 127;
    int repeats = c.byte();
    return {
        "Bar",
        {{"Style", choice({"Single", "Double", "Section Open", "Section Close",
                           "Local Repeat Open", "Local Repeat Close",
                           "Master Repeat Open", "Master Repeat Close"},
                          style)},
         {"Repeat", std::to_string(repeats)}}};
  }
  case 3: {
    int mask = c.byte();
    c.take(1);
    string endings;
    for (int i = 0; i < 8; ++i)
      if (mask & (1 << i)) {
        if (!endings.empty())
          endings += ",";
        endings += std::to_string(i + 1);
      }
    return {"Ending", {{"Numbers", endings}}};
  }
  case 4: {
    c.take(version < 0x146 ? 6 : 8);
    if (version >= 0x200) {
      string name = c.text();
      c.take(9);
      return {"Text", {{"Text", name}}};
    }
    return {"Text", {}};
  }
  case 5: {
    int beats = c.word(), power = c.word(), symbol = c.word();
    if (power > 6)
      throw std::runtime_error("Unknown meter");
    return {"TimeSig",
            {{"Signature", symbol == 1   ? "Common"
                           : symbol == 2 ? "AllaBreve"
                                         : std::to_string(beats) + "/" +
                                               std::to_string(1 << power)}}};
  }
  case 6: {
    c.take(2);
    int bpm = c.word(), base = c.byte();
    if (version < 0x146)
      c.take(2);
    return {"Tempo",
            {{"Tempo", std::to_string(bpm)},
             {"Text", c.text()},
             {"BeatUnit", choice({"eighth", "quarter", "half"}, base / 2)},
             {"BeatDot", std::to_string(base % 2)}}};
  }
  case 7: {
    int style = c.byte();
    c.take(1);
    if (version >= 0x146)
      style = c.byte();
    c.take(4);
    return {"Dynamic",
            {{"Style", choice({"ppp", "pp", "p", "mp", "mf", "f", "ff", "fff"},
                              style & 7)}}};
  }
  case 8:
  case 9:
    return tone(c, version, type == 9).event;
  case 11: {
    c.take(version >= 0x146 ? 2 : 3);
    return {"Pedal", {{"Action", choice({"stop", "start"}, c.byte())}}};
  }
  case 12: {
    if (version >= 0x146)
      c.take(2);
    return {"Text",
            {{"Text", choice({"Coda", "Segno", "Fine", "To Coda", "Da capo",
                              "D.C. al Coda", "D.C. al Fine", "Dal segno",
                              "D.S. al Coda", "D.S. al Fine"},
                             c.word())}}};
  }
  case 13:
    c.take(version <= 0x137 ? 32 : 34);
    return {"Text", {}}; // MIDI controller
  case 14: {
    Cursor fields = c.block(4);
    if (version >= 0x146)
      fields.take(2);
    return {"TempoVariance",
            {{"Style", choice({"Breath Mark", "Fermata", "Accelerando",
                               "Allargando", "Rallentando", "Ritardando",
                               "Ritenuto", "Rubato", "Stringendo"},
                              fields.byte() & 15)}}};
  }
  case 15: {
    c.take(version >= 0x146 ? 2 : 1);
    return {"DynamicVariance",
            {{"Style",
              choice({"cresc.", "decresc.", "dim.", "rfz", "sfz"}, c.byte())}}};
  }
  case 16: {
    Cursor fields = c.block(version >= 0x146 ? 3 : 2);
    if (version >= 0x146)
      fields.take(2);
    return {"PerformanceStyle",
            {{"Style",
              choice({"Ad libitum", "Animato",    "Cantabile",   "Con brio",
                      "Dolce",      "Espressivo", "Grazioso",    "Legato",
                      "Maestoso",   "Marcato",    "Meno mosso",  "Poco a poco",
                      "Più mosso",  "Semplice",   "Simile",      "Solo",
                      "Sostenuto",  "Sotto voce", "Staccato",    "Subito",
                      "Tenuto",     "Tutti",      "Volta subito"},
                     fields.byte())}}};
  }
  case 17:
    c.take(version >= 0x146 ? 3 : 2);
    return {"Text", {{"Text", c.text()}}};
  default:
    throw std::runtime_error("Unsupported legacy notation record " +
                             std::to_string(type));
  }
  return r;
}

void lyrics(Cursor &c, Staff &staff, int count) {
  for (int verse = 1; verse <= count; ++verse) {
    int size = c.word();
    if (!size)
      continue;
    c.take(2);
    Cursor block = c.block(size);
    block.take(2);
    auto &line = staff.lyrics[verse];
    while (block.pos < block.end) {
      string word = block.text();
      if (word.empty())
        break;
      auto first = word.find_first_not_of(" \t\r\n");
      if (first == string::npos)
        continue;
      word = word.substr(first, word.find_last_not_of(" \t\r\n") - first + 1);
      bool continuation = word.front() == '-';
      if (continuation && !line.empty()) {
        line.back().kind = line.back().kind == "single" ? "begin" : "middle";
        word.erase(0, 1);
      }
      line.push_back({word, continuation ? "end" : "single"});
    }
  }
}
} // namespace

Score readLegacy(const string &bytes, unsigned v) {
  const std::map<unsigned, int> staffHeader = {
      {0x11e, 26}, {0x132, 28}, {0x137, 29}, {0x146, 30},
      {0x14b, 31}, {0x200, 39}, {0x201, 39}};
  auto layout = staffHeader.find(v);
  if (layout == staffHeader.end())
    throw std::runtime_error("Unsupported NWC version");
  Cursor c(bytes, 47, bytes.size());
  Score score;
  c.take(4);
  c.text();
  c.text();
  c.take(10);
  auto &info = score.info.fields;
  info["Title"] = c.text();
  info["Author"] = c.text();
  if (v >= 0x200)
    info["Lyricist"] = c.text();
  info["Copyright1"] = c.text();
  info["Copyright2"] = c.text();
  c.text();
  c.take(11);
  for (int margin = 0; margin < 4; ++margin) {
    while (c.byte() > 32) {
    }
  }
  c.take(3);
  std::array<int, 32> visible;
  visible.fill(255);
  if (v > 0x11e) {
    for (int &mask : visible)
      mask = c.byte();
    c.take(1);
  }
  if (v >= 0x200)
    c.text();
  c.take(2);
  int fonts = v == 0x11e ? 0 : v <= 0x146 ? 10 : 12;
  for (int i = 0; i < fonts; ++i) {
    c.text();
    c.take(4);
  }
  if (v == 0x146 && c.peek() != 0 && c.peek() != 255)
    for (int i = 0; i < 2; ++i) {
      c.text();
      c.take(4);
    }
  c.take(4);
  if (v >= 0x200 && c.peek() == 255)
    c.take(1);
  int count = c.word();
  if (count < 1 || count > 64)
    throw std::runtime_error("Invalid staff count");
  size_t totalEvents = 0;
  for (int i = 0; i < count; ++i) {
    Staff staff;
    staff.legacyAccidentals = true;
    staff.name = c.text();
    if (v >= 0x200) {
      string label = c.text();
      if (!label.empty())
        staff.name = label;
      c.text();
    }
    c.text();
    staff.visible = visible[i / 8] & (1 << (i % 8));
    Cursor settings = c.block(layout->second);
    if (v != 0x11e) {
      settings.take(layout->second - (v >= 0x146 ? 9 : 8));
      staff.transpose = static_cast<int16_t>(settings.word());
    }
    int verses = c.word();
    if (v == 0x137 && verses == 0xcdcd)
      verses = 0;
    if (verses > 8)
      throw std::runtime_error("Invalid verse count");
    if (verses && v > 0x11e)
      c.take(4);
    lyrics(c, staff, verses);
    c.take(verses ? 4 : 2);
    int events = c.word() - (v > 0x132 ? 2 : 0);
    if (events < 0)
      throw std::runtime_error("Invalid event count");
    for (int j = 0; j < events; ++j) {
      int type = c.word();
      int display = v >= 0x146 ? c.byte() : 0;
      size_t before = staff.events.size();
      if (type == 10 || type == 18)
        chord(c, v, staff, type == 18);
      else
        staff.events.push_back(event(c, v, type));
      if ((display & 7) == 5)
        for (size_t k = before; k < staff.events.size(); ++k)
          staff.events[k].fields["Visibility"] = "Never";
      totalEvents += staff.events.size() - before;
      if (totalEvents > 120000)
        throw std::runtime_error("Score too large");
    }
    auto measure = staff.events.begin();
    while (measure != staff.events.end()) {
      auto bar = std::find_if(measure, staff.events.end(),
                              [](const Record &r) { return r.kind == "Bar"; });
      bool polyphonic = std::any_of(
          measure, bar, [](const Record &r) { return r.kind == "Rewind"; });
      if (polyphonic)
        for (auto it = measure; it != bar; ++it) {
          if (it->kind == "Note" || it->kind == "Chord" || it->kind == "Rest") {
            it->fields["Voice"] =
                it->get("Opts").find("Stem=Down") != string::npos ? "2" : "1";
            if (it->fields["Voice"] == "2")
              it->fields["Opts"] += ",Lyric=Never";
          }
        }
      if (bar == staff.events.end())
        break;
      measure = bar + 1;
    }
    score.staves.push_back(std::move(staff));
  }
  return score;
}
} // namespace score
