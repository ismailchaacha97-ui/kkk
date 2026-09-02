// Definitions for the MQL4 API stub declared in mql4_api_stub.h.

#include "mql4_api_stub.h"

double  g_point        = 0.00001;
int     g_digits       = 5;
double  g_bid          = 1.1000;
double  g_tick_value   = 1.0;
double  g_tick_size    = 0.00001;
double  g_balance      = 100.0;
int     g_leverage     = 500;
int     g_stopout_level = 50;

std::vector<datetime_>   g_time;
std::vector<StubOrder>   g_orders;
std::map<string, StubObject> g_objects;
std::vector<string>      g_alerts;
string                   g_comment;
int                      g_selected = 0;

// The indicator's own inputs, which `input` becomes once neutralised.
// Only define them here when the translation unit does not also compile the
// indicator itself - otherwise they collide at link time.
#ifndef NOLOSS_HAS_INPUTS
double InpBaseLot       = 0.01;
int    InpTakeProfit    = 20;
int    InpStep          = 30;
double InpMultiplier    = 2.0;
int    InpMaxRungs      = 12;
int    InpDirection     = 1;
double InpAnchorPrice   = 0.0;
int    InpMagic         = 0;
bool   InpAlertNextRung = false;
bool   InpAlertKillZone = false;
bool   InpShowPanel     = true;
double InpManualTickVal = 0.0;
#endif // NOLOSS_HAS_INPUTS

void Alert(const string &a, const string &b, const string &c,
           const string &d, const string &e)
{
   g_alerts.push_back(a + b + c + d + e);
}
