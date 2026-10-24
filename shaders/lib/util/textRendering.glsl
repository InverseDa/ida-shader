/*
--------------------------------------------------------------------------------

  GLSL Debug Text Renderer by SixthSurge (updated 2023-04-08)

  Character set based on Monocraft by IdreesInc
  https://github.com/IdreesInc/Monocraft

  With additional Characters added by WoMspace

  Usage:

  // Call BeginText to initialize the text renderer. You can scale the fragment position to adjust the size of the text
  BeginText(ivec2(gl_FragCoord.xy), ivec2(0, viewHeight));
            ^ fragment position     ^ text box position (upper left corner)

  // You can print various data types
  PrintBool(false);
  PrintFloat(sqrt(-1.0)); // Prints "NaN"
  PrintInt(42);
  PrintVec3(SkyColor);

  // ...or arbitrarily long strings
  PrintString((GlyphUpperH, GlyphLowerE, GlyphLowerL, GlyphLowerL, GlyphLowerO, GlyphComma, GlyphSpace, GlyphLowerW, GlyphLowerO, GlyphLowerR, GlyphLowerL, GlyphLowerD));

  // To start a new line, use
  PrintLine();

  // You can also configure the text color on the fly
  TextState.FgCol = vec4(1.0, 0.0, 0.0, 1.0);
  TextState.BgCol = vec4(0.0, 0.0, 0.0, 1.0);

  // ...as well as the number base and number of decimal places to print
  TextState.Base = 16;
  TextState.FpPrecision = 4;

  // Finally, call EndText to blend the current fragment color with the text
  EndText(FragColor);

  Important: any variables you display must be the same for all fragments, or
  at least all of the fragments that the text covers. Otherwise, different
  fragments will try to print different values, resulting in, well, a mess

--------------------------------------------------------------------------------
*/

#if !defined UTILITY_TEXTRENDERING_INCLUDED
#define UTILITY_TEXTRENDERING_INCLUDED

// Characters

const uint GlyphUpperA = 0x747f18c4u;
const uint GlyphUpperB = 0xf47d18f8u;
const uint GlyphUpperC = 0x746108b8u;
const uint GlyphUpperD = 0xf46318f8u;
const uint GlyphUpperE = 0xfc39087cu;
const uint GlyphUpperF = 0xfc390840u;
const uint GlyphUpperG = 0x7c2718b8u;
const uint GlyphUpperH = 0x8c7f18c4u;
const uint GlyphUpperI = 0x71084238u;
const uint GlyphUpperJ = 0x084218b8u;
const uint GlyphUpperK = 0x8cb928c4u;
const uint GlyphUpperL = 0x8421087cu;
const uint GlyphUpperM = 0x8eeb18c4u;
const uint GlyphUpperN = 0x8e6b38c4u;
const uint GlyphUpperO = 0x746318b8u;
const uint GlyphUpperP = 0xf47d0840u;
const uint GlyphUpperQ = 0x74631934u;
const uint GlyphUpperR = 0xf47d18c4u;
const uint GlyphUpperS = 0x7c1c18b8u;
const uint GlyphUpperT = 0xf9084210u;
const uint GlyphUpperU = 0x8c6318b8u;
const uint GlyphUpperV = 0x8c62a510u;
const uint GlyphUpperW = 0x8c635dc4u;
const uint GlyphUpperX = 0x8a88a8c4u;
const uint GlyphUpperY = 0x8a884210u;
const uint GlyphUpperZ = 0xf844447cu;
const uint GlyphLowerA = 0x0382f8bcu;
const uint GlyphLowerB = 0x85b318f8u;
const uint GlyphLowerC = 0x03a308b8u;
const uint GlyphLowerD = 0x0b6718bcu;
const uint GlyphLowerE = 0x03a3f83cu;
const uint GlyphLowerF = 0x323c8420u;
const uint GlyphLowerG = 0x03e2f0f8u;
const uint GlyphLowerH = 0x842d98c4u;
const uint GlyphLowerI = 0x40308418u;
const uint GlyphLowerJ = 0x080218b8u;
const uint GlyphLowerK = 0x4254c524u;
const uint GlyphLowerL = 0x6108420cu;
const uint GlyphLowerM = 0x06ab5ac4u;
const uint GlyphLowerN = 0x07a318c4u;
const uint GlyphLowerO = 0x03a318b8u;
const uint GlyphLowerP = 0x05b31f40u;
const uint GlyphLowerQ = 0x03671784u;
const uint GlyphLowerR = 0x05b30840u;
const uint GlyphLowerS = 0x03e0e0f8u;
const uint GlyphLowerT = 0x211c420cu;
const uint GlyphLowerU = 0x046318bcu;
const uint GlyphLowerV = 0x04631510u;
const uint GlyphLowerW = 0x04635abcu;
const uint GlyphLowerX = 0x04544544u;
const uint GlyphLowerY = 0x0462f0f8u;
const uint GlyphLowerZ = 0x07c4447cu;
const uint GlyphLower0 = 0x746b58b8u;
const uint GlyphLower1 = 0x23084238u;
const uint GlyphLower2 = 0x744c88fcu;
const uint GlyphLower3 = 0x744c18b8u;
const uint GlyphLower4 = 0x19531f84u;
const uint GlyphLower5 = 0xfc3c18b8u;
const uint GlyphLower6 = 0x3221e8b8u;
const uint GlyphLower7 = 0xfc422210u;
const uint GlyphLower8 = 0x745d18b8u;
const uint GlyphLower9 = 0x745e1130u;
const uint GlyphSpace = 0x0000000u;
const uint GlyphDot = 0x000010u;
const uint GlyphMinus = 0x0000e000u;
const uint GlyphComma = 0x00000220u;
const uint GlyphColon = 0x02000020u;

// Additional Characters added by WoMspace <3
const uint GlyphUnder = 0x000007Cu;  // _
const uint GlyphQuote = 0x52800000u; // "
const uint GlyphExclm = 0x21084010u; // !
const uint GlyphGt = 0x02082220u;    // >
const uint GlyphLt = 0x00888208u;    // <
const uint GlyphOpsqr = 0x3908421Cu; // [
const uint GlyphClsqr = 0xE1084270u; // ]
const uint GlyphOpprn = 0x11084208u; // (
const uint GlyphClprn = 0x41084220u; // )
const uint GlyphBlock = 0xFFFFFFFCu; // █
const uint GlyphCopyr = 0x03AB9AB8u; // ©️

const int CharWidth = 5;
const int CharHeight = 6;
const int CharSpacing = 1;
const int LineSpacing = 1;

const ivec2 CharSize = ivec2(CharWidth, CharHeight);
const ivec2 SpaceSize = CharSize + ivec2(CharSpacing, LineSpacing);

// Text renderer

struct Text {
    vec4 Result;     // Output color from the text renderer
    vec4 FgCol;      // Text foreground color
    vec4 BgCol;      // Text background color
    ivec2 FragPos;   // The position of the fragment (can be scaled to adjust the size of the text)
    ivec2 TextPos;   // The position of the top-left corner of the text
    ivec2 CharPos;   // The position of the next character in the text
    int Base;        // Number base
    int FpPrecision; // Number of decimal places to print
} TextState;

// Fills the global text object with default values
void BeginText(ivec2 FragPos, ivec2 TextPos) {
    TextState.Result = vec4(0.0);
    TextState.FgCol = vec4(1.0);
    TextState.BgCol = vec4(0.0, 0.0, 0.0, 0.6);
    TextState.FragPos = FragPos;
    TextState.TextPos = TextPos;
    TextState.CharPos = ivec2(0);
    TextState.Base = 10;
    TextState.FpPrecision = 2;
}

// Applies the rendered text to the fragment
void EndText(inout vec3 FragColor) {
    FragColor = mix(FragColor.rgb, TextState.Result.rgb, TextState.Result.a);
}

void PrintChar(uint Character) {
    ivec2 Pos = TextState.FragPos - TextState.TextPos - SpaceSize * TextState.CharPos * ivec2(1, -1) + ivec2(0, SpaceSize.y);

    uint Index = uint(CharWidth - Pos.x + Pos.y * CharWidth + 1); // Edited

    // Draw background
    if (clamp(Pos, ivec2(0), SpaceSize - 1) == Pos)
        TextState.Result = mix(TextState.Result, TextState.BgCol, TextState.BgCol.a);

    // Draw character
    if (clamp(Pos, ivec2(0), CharSize - 1) == Pos)
        TextState.Result = mix(TextState.Result, TextState.FgCol, TextState.FgCol.a * float(Character >> Index & 1u));

    // Advance to next character
    TextState.CharPos.x++;
}

#define PrintString(String)                           \
    {                                                 \
        uint[] Characters = uint[] String;            \
        for (int I = 0; I < Characters.length(); ++I) \
            PrintChar(Characters[I]);                 \
    }

void PrintUnsignedInt(uint Value, int Len) {
    const uint[36] Digits = uint[](GlyphLower0, GlyphLower1, GlyphLower2, GlyphLower3, GlyphLower4, GlyphLower5, GlyphLower6, GlyphLower7, GlyphLower8, GlyphLower9, GlyphLowerA, GlyphLowerB, GlyphLowerC, GlyphLowerD, GlyphLowerE, GlyphLowerF, GlyphLowerG, GlyphLowerH, GlyphLowerI, GlyphLowerJ, GlyphLowerK, GlyphLowerL, GlyphLowerM, GlyphLowerN, GlyphLowerO, GlyphLowerP, GlyphLowerQ, GlyphLowerR, GlyphLowerS, GlyphLowerT, GlyphLowerU, GlyphLowerV, GlyphLowerW, GlyphLowerX, GlyphLowerY, GlyphLowerZ);

    // Advance to end of the number
    TextState.CharPos.x += Len - 1;

    // Write number backwards
    for (int I = 0; I < Len; ++I) {
        PrintChar(Digits[int(Value) % TextState.Base]); // Edited
        Value /= uint(TextState.Base);                  // Edited
        TextState.CharPos.x -= 2;
    }

    // Return to end of the number
    TextState.CharPos.x += Len + 1;
}

void PrintUnsignedInt(uint Value) {
    float LogValue = log(float(Value)) + 1e-6;
    float LogBase = log(float(TextState.Base));

    int Len = int(ceil(LogValue / LogBase));
    Len = max(Len, 1);

    PrintUnsignedInt(Value, Len);
}

void PrintInt(int Value) {
    if (Value < 0) PrintChar(GlyphMinus);
    PrintUnsignedInt(uint(abs(Value)));
}

void PrintFloat(float Value) {
    if (Value < 0.0) PrintChar(GlyphMinus);

    if (isnan(Value)) {
        PrintString((GlyphUpperN, GlyphLowerA, GlyphUpperN));
    } else if (isinf(Value)) {
        PrintString((GlyphLowerI, GlyphLowerN, GlyphLowerF));
    } else {
        float I, F = modf(abs(Value), I);

        uint IntegralPart = uint(I);
        uint FractionalPart = uint(F * pow(float(TextState.Base), float(TextState.FpPrecision)) + 0.5);

        PrintUnsignedInt(IntegralPart);
        PrintChar(GlyphDot);
        PrintUnsignedInt(FractionalPart, TextState.FpPrecision);
    }
}

void PrintBool(bool Value) {
    if (Value) {
        PrintString((GlyphLowerT, GlyphLowerR, GlyphLowerU, GlyphLowerE));
    } else {
        PrintString((GlyphLowerF, GlyphLowerA, GlyphLowerL, GlyphLowerS, GlyphLowerE));
    }
}

void PrintVec2(vec2 Value) {
    PrintFloat(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintFloat(Value.y);
}

void PrintVec3(vec3 Value) {
    PrintFloat(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintFloat(Value.y);
    PrintString((GlyphComma, GlyphSpace));
    PrintFloat(Value.z);
}

void PrintVec4(vec4 Value) {
    PrintFloat(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintFloat(Value.y);
    PrintString((GlyphComma, GlyphSpace));
    PrintFloat(Value.z);
    PrintString((GlyphComma, GlyphSpace));
    PrintFloat(Value.w);
}

void PrintIvec2(ivec2 Value) {
    PrintInt(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintInt(Value.y);
}

void PrintIvec3(ivec3 Value) {
    PrintInt(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintInt(Value.y);
    PrintString((GlyphComma, GlyphSpace));
    PrintInt(Value.z);
}

void PrintIvec4(ivec4 Value) {
    PrintInt(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintInt(Value.y);
    PrintString((GlyphComma, GlyphSpace));
    PrintInt(Value.z);
    PrintString((GlyphComma, GlyphSpace));
    PrintInt(Value.w);
}

void PrintUvec2(uvec2 Value) {
    PrintUnsignedInt(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintUnsignedInt(Value.y);
}

void PrintUvec3(uvec3 Value) {
    PrintUnsignedInt(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintUnsignedInt(Value.y);
    PrintString((GlyphComma, GlyphSpace));
    PrintUnsignedInt(Value.z);
}

void PrintUvec4(uvec4 Value) {
    PrintUnsignedInt(Value.x);
    PrintString((GlyphComma, GlyphSpace));
    PrintUnsignedInt(Value.y);
    PrintString((GlyphComma, GlyphSpace));
    PrintUnsignedInt(Value.z);
    PrintString((GlyphComma, GlyphSpace));
    PrintUnsignedInt(Value.w);
}

void PrintLine() {
    TextState.CharPos.x = 0;
    ++TextState.CharPos.y;
}

#endif // UTILITY_TEXTRENDERING_INCLUDED