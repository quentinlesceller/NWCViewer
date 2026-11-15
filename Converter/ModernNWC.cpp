// NWC Viewer: bounded NWC 2.75/NWCTXT-container to MusicXML conversion.
// GPL-2.0-only. No network, external runtimes, or modification of the input.
#include "ModernNWC.h"
#include <zlib.h>
#include <algorithm>
#include <fstream>
#include <sstream>
#include <map>
#include <set>
#include <vector>
#include <regex>
#include <stdexcept>
#include <cstdio>
#include <cstring>

namespace {
using std::string;
const size_t LIMIT = 32*1024*1024;
string esc(const string& s) {
    string out;
    for (unsigned char c : s) {
        switch(c) { case '&': out+="&amp;";break; case '<':out+="&lt;";break;
        case '>':out+="&gt;";break;case '"':out+="&quot;";break;
        default: if(c>=32 || c=='\n' || c=='\t') out+=c; }
    }
    return out;
}
string tag(const string& key,const string& value) {return "<"+key+">"+esc(value)+"</"+key+">";}
string tag(const string& key,int value) {return tag(key,std::to_string(value));}
std::vector<string> split(const string& s,char sep) {
    std::vector<string> a;string word;bool quoted=false,escaped=false;
    for(char c:s) {
        if(c==sep && !quoted) {a.push_back(word);word.clear();continue;}
        word+=c;
        if(escaped) {escaped=false;continue;}
        if(c=='\\') escaped=true; else if(c=='"' && sep=='|') quoted=!quoted;
    }
    if(quoted) throw std::runtime_error("Unterminated quoted field");
    a.push_back(word);return a;
}
string unquote(string s) {
    if(s.size()<2 || s.front()!='"' || s.back()!='"') return s;
    string out;
    for(size_t i=1;i+1<s.size();++i) {
        char c=s[i];
        if(c=='\\' && i+2<s.size()) {c=s[++i];if(c=='n')c='\n';else if(c=='r')c='\r';else if(c=='t')c='\t';}
        out+=c;
    }
    return out;
}
int number(const string& s,int lo,int hi) {
    size_t end=0;int n=std::stoi(s,&end);
    if(end!=s.size() || n<lo || n>hi) throw std::runtime_error("Invalid numeric field");
    return n;
}
struct Record {
    string kind;std::map<string,string> fields;
    string get(const string& key,const string& def="") const {auto i=fields.find(key);return i==fields.end()?def:i->second;}
};
Record record(const string& line) {
    auto a=split(line,'|');if(a.size()<2)throw std::runtime_error("Invalid record");
    Record r;r.kind=a[1];
    for(size_t i=2;i<a.size();i++) {size_t p=a[i].find(':');if(p==string::npos)throw std::runtime_error("Invalid field");r.fields[a[i].substr(0,p)]=unquote(a[i].substr(p+1));}
    return r;
}
bool has(const string& options,const string& item) {auto a=split(options,',');return std::find(a.begin(),a.end(),item)!=a.end();}
struct Syllable {string text,kind;};
std::vector<Syllable> syllables(const string& text) {
    std::istringstream in(text);string word;std::vector<Syllable> out;
    while(in>>word) {
        auto chunks=split(word,'-');
        for(size_t i=0;i<chunks.size();i++) {
            string s=chunks[i];if(s.empty())continue;
            if(s=="_") s="";else std::replace(s.begin(),s.end(),'_',' ');
            out.push_back({s,chunks.size()==1?"single":i==0?"begin":i+1==chunks.size()?"end":"middle"});
        }
    }
    return out;
}
struct Staff {string name,abbreviation;bool visible=true;int transpose=0;std::vector<Record> events;std::map<int,std::vector<Syllable>> lyrics;};
struct Duration {int ticks,dots,beams;bool triplet,grace,slur;string type;};
Duration duration(const string& value) {
    auto a=split(value,',');const std::map<string,std::pair<int,string>> types={
        {"Whole",{1920,"whole"}},{"Half",{960,"half"}},{"4th",{480,"quarter"}},
        {"8th",{240,"eighth"}},{"16th",{120,"16th"}},{"32nd",{60,"32nd"}},{"64th",{30,"64th"}}};
    auto it=types.find(a[0]);if(it==types.end())throw std::runtime_error("Unsupported note duration");
    Duration d={it->second.first,0,0,false,false,false,it->second.second};
    d.dots=has(value,"DblDotted")?2:has(value,"Dotted")?1:0;
    if(d.dots==1)d.ticks=d.ticks*3/2;if(d.dots==2)d.ticks=d.ticks*7/4;
    d.triplet=value.find("Triplet")!=string::npos;if(d.triplet)d.ticks=d.ticks*2/3;
    d.grace=has(value,"Grace");d.slur=has(value,"Slur");
    if(d.type=="eighth")d.beams=1;else if(d.type=="16th")d.beams=2;else if(d.type=="32nd")d.beams=3;else if(d.type=="64th")d.beams=4;
    return d;
}
struct Part {
    int middle=34,octaveShift=0,beats=4,beatType=4,measure=1,elapsed=0;
    std::map<int,int> accidentals,ties;std::map<char,int> key;
    bool slur=false,fermata=false,started=false;string wedge;
    std::map<int,size_t> lyricIndex;std::ostringstream xml;
    int barTicks()const{return beats*1920/beatType;}
    void start(int transpose) {xml<<"<measure number=\""<<measure<<"\"><attributes><divisions>480</divisions>";
        if(transpose)xml<<"<transpose>"<<tag("chromatic",transpose)<<"</transpose>";
        xml<<"</attributes>";started=true;}
    void next() {xml<<"</measure>";measure++;elapsed=0;accidentals.clear();xml<<"<measure number=\""<<measure<<"\">";}
    void words(const string& text){if(!text.empty())xml<<"<direction placement=\"above\"><direction-type>"<<tag("words",text)<<"</direction-type></direction>";}
    void closeWedge(){if(!wedge.empty()){xml<<"<direction><direction-type><wedge type=\"stop\"/></direction-type></direction>";wedge.clear();}}
};
string partXML(const Staff& source,int index) {
    Staff staff=source;
    // NWC places a courtesy time change before the preceding barline.
    for(size_t i=0;i<staff.events.size();++i) if(staff.events[i].kind=="TimeSig") {
        size_t j=i+1;
        while(j<staff.events.size() && (staff.events[j].kind=="PerformanceStyle" || staff.events[j].kind=="Tempo"))++j;
        if(j<staff.events.size() && staff.events[j].kind=="Bar") {
            Record time=staff.events[i];staff.events.erase(staff.events.begin()+i);staff.events.insert(staff.events.begin()+j,time);i=j;
        }
    }
    Part p;p.start(staff.transpose);
    for(size_t ri=0;ri<staff.events.size();++ri) {
        const Record& r=staff.events[ri];string k=r.kind;
        if(k=="Clef") {
            string clef=r.get("Type");string sign;int line=0;
            if(clef=="Treble"){p.middle=34;sign="G";line=2;}
            else if(clef=="Bass"){p.middle=22;sign="F";line=4;}
            else if(clef=="Alto"){p.middle=28;sign="C";line=3;}
            else if(clef=="Tenor"){p.middle=26;sign="C";line=4;}
            else throw std::runtime_error("Unsupported clef");
            p.octaveShift=r.get("OctaveShift")=="Octave Up"?1:r.get("OctaveShift")=="Octave Down"?-1:0;
            p.xml<<"<attributes><clef>"<<tag("sign",sign)<<tag("line",line);
            if(p.octaveShift)p.xml<<tag("clef-octave-change",p.octaveShift);
            p.xml<<"</clef></attributes>";
        } else if(k=="Key") {
            string sig=r.get("Signature");p.key.clear();int fifths=0;
            if(!sig.empty()) for(auto s:split(sig,',')) {
                if(s.size()!=2 || string("ABCDEFG").find(s[0])==string::npos || (s[1]!='#'&&s[1]!='b'))throw std::runtime_error("Unsupported key signature");
                int alter=s[1]=='#'?1:-1;p.key[s[0]]=alter;fifths+=alter;
            }
            string order=fifths>=0?"FCGDAEB":"BEADGCF";
            if(std::abs(fifths)!=(int)p.key.size())throw std::runtime_error("Mixed key signature");
            for(int i=0;i<std::abs(fifths);i++)if(!p.key.count(order[i]))throw std::runtime_error("Custom key signature");
            p.accidentals.clear();p.xml<<"<attributes><key>"<<tag("fifths",fifths)<<"</key></attributes>";
        } else if(k=="TimeSig") {
            string sig=r.get("Signature");string symbol;
            if(sig=="Common"){sig="4/4";symbol=" symbol=\"common\"";}else if(sig=="AllaBreve"){sig="2/2";symbol=" symbol=\"cut\"";}
            auto a=split(sig,'/');if(a.size()!=2)throw std::runtime_error("Unsupported time signature");
            p.beats=number(a[0],1,64);p.beatType=number(a[1],1,64);
            if((p.beatType&(p.beatType-1))!=0)throw std::runtime_error("Invalid time denominator");
            p.xml<<"<attributes><time"<<symbol<<">"<<tag("beats",p.beats)<<tag("beat-type",p.beatType)<<"</time></attributes>";
        } else if(k=="Bar") {
            if(p.elapsed>p.barTicks())throw std::runtime_error("Overfull measure " + staff.name + " " + std::to_string(p.measure) + " ticks " + std::to_string(p.elapsed));
            string style=r.get("Style");
            if(!style.empty() && style!="Single") {
                string bar=style=="Double"?"light-light":style=="Section Open"?"heavy-light":"light-heavy";
                p.xml<<"<barline location=\"right\">"<<tag("bar-style",bar);
                if(style.find("Repeat Close")!=string::npos)p.xml<<"<repeat direction=\"backward\"/>";
                p.xml<<"</barline>";
            }
            if(ri+1<staff.events.size())p.next();
        } else if(k=="RestMultiBar") {
            if(p.elapsed)throw std::runtime_error("Multi-measure rest inside a measure");
            int count=number(r.get("NumBars"),1,2000);
            for(int i=0;i<count;i++){if(i)p.next();p.xml<<"<note><rest measure=\"yes\"/>"<<tag("duration",p.barTicks())<<"</note>";p.elapsed=p.barTicks();}
        } else if(k=="Note" || k=="Chord" || k=="Rest") {
            if(!r.get("Dur2").empty() || !r.get("Pos2").empty())throw std::runtime_error("Split-duration chord is not supported yet");
            Duration d=duration(r.get("Dur"));bool rest=k=="Rest";
            bool wholeRest=rest && r.get("Dur")=="Whole" && p.elapsed==0;
            for(size_t j=ri+1;wholeRest && j<staff.events.size() && staff.events[j].kind!="Bar";++j)
                if(staff.events[j].kind=="Note" || staff.events[j].kind=="Chord" || staff.events[j].kind=="Rest")wholeRest=false;
            int ticks=wholeRest?p.barTicks():d.ticks;
            string opts=r.get("Opts"),newWedge=has(opts,"Crescendo")?"crescendo":has(opts,"Diminuendo")?"diminuendo":"";
            if(newWedge!=p.wedge){p.closeWedge();if(!newWedge.empty()){p.wedge=newWedge;p.xml<<"<direction><direction-type><wedge type=\""<<newWedge<<"\"/></direction-type></direction>";}}
            auto positions=rest?std::vector<string>{""}:split(r.get("Pos"),',');if(positions.empty() || positions.size()>64)throw std::runtime_error("Invalid chord");
            bool priorSlur=p.slur;
            for(size_t ni=0;ni<positions.size();ni++) {
                bool stopTie=false,startTie=false,cautionary=false;int pitch=0,alter=0;char step='C';int octave=4;string explicitAcc,notehead;
                if(!rest) {
                    string pos=positions[ni];size_t bang=pos.find('!');if(bang!=string::npos)pos.resize(bang);
                    cautionary=pos.find(')')!=string::npos;pos.erase(std::remove(pos.begin(),pos.end(),')'),pos.end());
                    startTie=pos.find('^')!=string::npos;
                    std::smatch m;static const std::regex pattern("^([#nbxv]?)(-?[0-9]+)([xXzo]?)(\\^?)$");
                    if(!std::regex_match(pos,m,pattern))throw std::runtime_error("Unsupported note position: " + pos);
                    pitch=p.middle+number(m[2],-70,70);if(pitch<0||pitch>76)throw std::runtime_error("Pitch out of range");
                    step=string("CDEFGAB")[pitch%7];octave=pitch/7+p.octaveShift;
                    stopTie=p.ties.count(pitch);alter=p.accidentals.count(pitch)?p.accidentals[pitch]:p.key[step];
                    if(stopTie)alter=p.ties[pitch];
                    if(!m[1].str().empty()) {
                        char a=m[1].str()[0];alter=a=='#'?1:a=='b'?-1:a=='x'?2:a=='v'?-2:0;
                        explicitAcc=a=='#'?"sharp":a=='b'?"flat":a=='x'?"double-sharp":a=='v'?"flat-flat":"natural";
                        p.accidentals[pitch]=alter;
                    }
                    if(startTie)p.ties[pitch]=alter;else p.ties.erase(pitch);
                    string h=m[3];notehead=h=="x"?"x":h=="X"?"diamond":h=="z"?"none":"";
                }
                p.xml<<"<note"<<(r.get("Visibility")=="Never"?" print-object=\"no\"":"")<<">";
                if(d.grace)p.xml<<"<grace/>";if(ni)p.xml<<"<chord/>";
                if(rest)p.xml<<(wholeRest?"<rest measure=\"yes\"/>":"<rest/>");
                else {p.xml<<"<pitch>"<<tag("step",string(1,step));if(alter)p.xml<<tag("alter",alter);p.xml<<tag("octave",octave)<<"</pitch>";}
                if(!d.grace)p.xml<<tag("duration",ticks);
                if(stopTie)p.xml<<"<tie type=\"stop\"/>";if(startTie)p.xml<<"<tie type=\"start\"/>";
                if(!wholeRest){p.xml<<tag("type",d.type);for(int i=0;i<d.dots;i++)p.xml<<"<dot/>";}
                if(!explicitAcc.empty())p.xml<<"<accidental"<<(cautionary?" parentheses=\"yes\"":"")<<">"<<explicitAcc<<"</accidental>";
                if(d.triplet)p.xml<<"<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>";
                if(has(opts,"Stem=Up"))p.xml<<tag("stem","up");else if(has(opts,"Stem=Down"))p.xml<<tag("stem","down");
                if(!notehead.empty())p.xml<<tag("notehead",notehead);
                for(int i=1;!rest && i<=d.beams;i++) {
                    string beam=has(opts,"Beam=First")?"begin":has(opts,"Beam=End")?"end":has(opts,"Beam")?"continue":"";
                    if(!beam.empty())p.xml<<"<beam number=\""<<i<<"\">"<<beam<<"</beam>";
                }
                p.xml<<"<notations>";
                if(stopTie)p.xml<<"<tied type=\"stop\"/>";if(startTie)p.xml<<"<tied type=\"start\"/>";
                if(ni==0){
                    if(priorSlur&&!d.slur)p.xml<<"<slur type=\"stop\" number=\"1\"/>";
                    if(!priorSlur&&d.slur)p.xml<<"<slur type=\"start\" number=\"1\"/>";
                    if(p.fermata)p.xml<<"<fermata/>";
                    if(has(r.get("Dur"),"Triplet=First"))p.xml<<"<tuplet type=\"start\"/>";
                    if(has(r.get("Dur"),"Triplet=End"))p.xml<<"<tuplet type=\"stop\"/>";
                    string articulation;
                    for(auto a:std::vector<std::pair<string,string>>{{"Staccato","staccato"},{"Accent","accent"},{"Tenuto","tenuto"}})if(has(r.get("Dur"),a.first))articulation+="<"+a.second+"/>";
                    if(!articulation.empty())p.xml<<"<articulations>"<<articulation<<"</articulations>";
                }
                p.xml<<"</notations>";
                if(ni==0&&!rest&&!d.grace&&!has(opts,"Lyric=Never") && (has(opts,"Lyric=Always")||(!priorSlur&&!stopTie))) {
                    for(auto& verse:staff.lyrics){size_t at=p.lyricIndex[verse.first]++;if(at>=verse.second.size())continue;auto syllable=verse.second[at];
                        if(!syllable.text.empty())p.xml<<"<lyric number=\""<<verse.first<<"\">"<<tag("syllabic",syllable.kind)<<tag("text",syllable.text)<<"</lyric>";}
                }
                p.xml<<"</note>";
            }
            p.fermata=false;p.slur=d.slur;if(!d.grace)p.elapsed+=ticks;
        } else if(k=="TempoVariance" && r.get("Style")=="Fermata") {p.fermata=true;
        } else if(k=="Dynamic") {
            p.closeWedge();string style=r.get("Style");static const std::set<string> allowed={"ppp","pp","p","mp","mf","f","ff","fff","sfz","sffz","fp"};
            if(!allowed.count(style))throw std::runtime_error("Unsupported dynamic");
            if(r.get("Visibility")!="Never")p.xml<<"<direction placement=\"below\"><direction-type><dynamics><"<<style<<"/></dynamics></direction-type></direction>";
        } else if(k=="Tempo") {
            if(r.get("Visibility")!="Never"){p.words(r.get("Text"));p.xml<<"<direction><direction-type><metronome>"<<tag("beat-unit","quarter")<<tag("per-minute",number(r.get("Tempo"),1,1000))<<"</metronome></direction-type></direction>";}
        } else if(k=="PerformanceStyle" || k=="DynamicVariance" || k=="TempoVariance") {
            if(r.get("Visibility")!="Never")p.words(r.get("Style"));
        } else if(k=="Text") {if(r.get("Visibility")!="Never")p.words(r.get("Text"));
        } else {throw std::runtime_error("Unsupported musical record: "+k);}
        if(p.xml.tellp()>(std::streamoff)LIMIT)throw std::runtime_error("Score XML too large");
    }
    p.closeWedge();p.xml<<"<barline location=\"right\"><bar-style>light-heavy</bar-style></barline></measure>";
    return "<part id=\"P"+std::to_string(index)+"\">"+p.xml.str()+"</part>";
}
string convert(const string& text) {
    std::vector<Staff> staves;Record info;std::istringstream input(text);string line;bool end=false;
    while(std::getline(input,line)) {
        if(!line.empty()&&line.back()=='\r')line.pop_back();
        if(line=="!NoteWorthyComposer-End"){end=true;break;}
        if(line.empty()||line[0]=='!')continue;
        Record r=record(line);string k=r.kind;
        if(k=="SongInfo"){info=r;continue;}
        if(k=="AddStaff"){if(staves.size()>=64)throw std::runtime_error("Too many staves");Staff staff;staff.name=r.get("Label",r.get("Name","Staff"));staff.abbreviation=r.get("LabelAbbr");staves.push_back(staff);continue;}
        if(k=="Editor"||k=="PgSetup"||k=="Font"||k=="PgMargins")continue;
        if(staves.empty())throw std::runtime_error("Record outside staff");Staff& staff=staves.back();
        if(k=="StaffProperties"){if(r.get("Visible")=="N")staff.visible=false;continue;}
        if(k=="StaffInstrument"){staff.transpose=number(r.get("Trans","0"),-48,48);continue;}
        if(k=="Lyrics")continue;
        if(k.size()==6&&k.substr(0,5)=="Lyric"&&k[5]>='1'&&k[5]<='8'){staff.lyrics[k[5]-'0']=syllables(r.get("Text"));continue;}
        staff.events.push_back(r);
    }
    if(!end||staves.empty())throw std::runtime_error("Incomplete score");
    string xml="<?xml version=\"1.0\" encoding=\"UTF-8\"?><score-partwise version=\"4.0\"><work>"+tag("work-title",info.get("Title"))+"</work><identification><creator type=\"composer\">"+esc(info.get("Author"))+"</creator>";
    if(!info.get("Lyricist").empty())xml+="<creator type=\"lyricist\">"+esc(info.get("Lyricist"))+"</creator>";
    xml+=tag("rights",info.get("Copyright1")+" "+info.get("Copyright2"))+"</identification><part-list>";
    int index=0;for(auto& s:staves)if(s.visible){++index;xml+="<score-part id=\"P"+std::to_string(index)+"\">"+tag("part-name",s.name);if(!s.abbreviation.empty())xml+=tag("part-abbreviation",s.abbreviation);xml+="</score-part>";}
    xml+="</part-list>";index=0;for(auto& s:staves)if(s.visible){xml+=partXML(s,++index);if(xml.size()>LIMIT)throw std::runtime_error("Score XML too large");}
    if(!index)throw std::runtime_error("No visible staves");return xml+"</score-partwise>";
}
}
int ConvertModernNWC(const char* input,const char* output) {
    try {
        std::ifstream file(input,std::ios::binary|std::ios::ate);if(!file)return -1;
        auto size=file.tellg();if(size<=0 || size>16*1024*1024)return -1;
        string data((size_t)size,'\0');file.seekg(0);file.read(&data[0],size);
        if(data.compare(0,6,string("[NWZ]\0",6))==0) {
            z_stream z={};if(inflateInit(&z)!=Z_OK)throw std::runtime_error("Unable to decompress");
            z.next_in=(Bytef*)data.data()+6;z.avail_in=(uInt)data.size()-6;string expanded;char buffer[16384];int status;
            do {z.next_out=(Bytef*)buffer;z.avail_out=sizeof(buffer);status=inflate(&z,Z_NO_FLUSH);expanded.append(buffer,sizeof(buffer)-z.avail_out);if(expanded.size()>LIMIT){inflateEnd(&z);throw std::runtime_error("Expanded score too large");}}while(status==Z_OK);
            inflateEnd(&z);if(status!=Z_STREAM_END)throw std::runtime_error("Damaged compressed score");data.swap(expanded);
        }
        const string header("[NoteWorthy ArtWare]\0\0\0[NoteWorthy Composer]\0",45);
        if(data.size()<47||data.compare(0,header.size(),header)!=0)return -1;
        unsigned version=(unsigned char)data[45]|((unsigned char)data[46]<<8);
        if(version!=0x024b)return -1;
        size_t marker=data.find("!NoteWorthyComposer(2.75");
        if(marker==string::npos||marker>4096)throw std::runtime_error("Missing modern score text");
        string xml=convert(data.substr(marker));std::ofstream dest(output,std::ios::binary);dest<<xml;if(!dest)throw std::runtime_error("Unable to write score");return 0;
    } catch(const std::exception& e) {std::fprintf(stderr,"NWC 2.75: %s\n",e.what());std::remove(output);return 1;}
}
