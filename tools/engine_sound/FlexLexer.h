// Minimal stand-in for flex's FlexLexer.h: the piranha scanner is hand-written (scanner_hand.cpp) instead of
// generated, so the base class only holds the input stream and the current token text.
#pragma once
#include <istream>
#include <string>
#define yyFlexLexerOnce
class FlexLexer {
public:
    virtual ~FlexLexer() {}
    virtual int yylex() { return 0; }
};
class yyFlexLexer : public FlexLexer {
public:
    yyFlexLexer(std::istream *in) : m_in(in) {}
    virtual ~yyFlexLexer() {}
protected:
    int peekc() { return m_in->peek(); }
    int getc() { int c = m_in->get(); return c == EOF ? 0 : c; }
    int yyinput() { return getc(); }
    void LexerError(const char *msg);
    std::istream *m_in;
    std::string m_text;
    const char *yytext_c() const { return m_text.c_str(); }
};
