#include "../Vendor/nwc2xml/Precompile.h"
#include "../Vendor/nwc2xml/nwcfile.h"
extern DWORD ConvertNWC2MusicXML(const wxString&, bool);
extern "C" int NWCPadConvert(const char *path) {
    try {
        g_pMBConv = &wxConvLocal;
        return ConvertNWC2MusicXML(wxString(path), false);
    } catch (...) { return 1; }
}
