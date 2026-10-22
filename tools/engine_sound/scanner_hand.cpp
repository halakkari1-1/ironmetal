// Hand-written equivalent of piranha's flex-bison/scanner.l (same tokens, same location tracking).
#include <string>
#include <iostream>
#include <cctype>
#include <cstring>
#include "../include/scanner.h"

using token = piranha::Parser::token;
#define yytext (m_text.c_str())
#define DEFAULT_BUILD(location) buildValue<std::string>(m_text, (location), true)
#define BUILD_INVALID(location) buildValue<std::string>(m_text, (location), false)

void yyFlexLexer::LexerError(const char *msg) { std::cerr << "lexer: " << msg << std::endl; }

static bool isL(int c) { return std::isalpha(c) || c == '_'; }
static bool isD(int c) { return c >= '0' && c <= '9'; }

int piranha::Scanner::yylex(piranha::Parser::semantic_type *const lval, piranha::Parser::location_type *location) {
    m_yylval = lval;
    for (;;) {
        m_text.clear();
        int c = getc();
        if (c == 0) return token::END;
        m_text += (char)c;
        // whitespace
        if (c == ' ' || c == '\t' || c == '\v' || c == '\n' || c == '\f' || c == '\r') { count(); continue; }
        // comments
        if (c == '/' && peekc() == '/') {
            while (peekc() != EOF && peekc() != '\n') m_text += (char)getc();
            count(); continue;
        }
        if (c == '/' && peekc() == '*') { m_text += (char)getc(); count(); comment(); continue; }
        if (isL(c)) {
            while (isL(peekc()) || isD(peekc())) m_text += (char)getc();
            count();
            static const struct { const char *k; int t; } kw[] = {
                {"import", token::IMPORT}, {"as", token::AS}, {"input", token::INPUT}, {"output", token::OUTPUT},
                {"modify", token::MODIFY}, {"toggle", token::TOGGLE}, {"alias", token::ALIAS}, {"inline", token::INLINE},
                {"auto", token::AUTO}, {"node", token::NODE}, {"public", token::PUBLIC}, {"private", token::PRIVATE},
                {"operator", token::OPERATOR}, {"module", token::MODULE}};
            for (auto &k : kw) if (m_text == k.k) { DEFAULT_BUILD(location); return k.t; }
            if (m_text == "true") { buildValue<bool>(true, location); return token::BOOL; }
            if (m_text == "false") { buildValue<bool>(false, location); return token::BOOL; }
            DEFAULT_BUILD(location); return token::LABEL;
        }
        if (isD(c)) {
            if (c == '0' && (peekc() == 'x' || peekc() == 'X')) {
                m_text += (char)getc();
                while (std::isxdigit(peekc())) m_text += (char)getc();
                count(); buildValue<int>((int)std::stoul(m_text, nullptr, 16), location); return token::INT;
            }
            while (isD(peekc())) m_text += (char)getc();
            if (peekc() == '.') {
                // FLOAT needs digits after the dot; otherwise the dot is its own token
                m_in->get();
                if (isD(peekc())) {
                    m_text += '.';
                    while (isD(peekc())) m_text += (char)getc();
                    count(); buildValue<double>(std::stod(m_text), location); return token::FLOAT;
                }
                m_in->unget();
            }
            count(); buildValue<int>((int)std::stoul(m_text, nullptr, 10), location); return token::INT;
        }
        if (c == '"') {
            bool ok = false;
            while (peekc() != EOF) {
                int d = getc();
                if (d == '\n') { m_in->unget(); break; }
                m_text += (char)d;
                if (d == '\\') { int e = getc(); m_text += (char)e; continue; }
                if (d == '"') { ok = true; break; }
            }
            count();
            if (!ok) { BUILD_INVALID(location); return token::UNRECOGNIZED; }
            buildValue<std::string>(m_text.substr(1, m_text.size() - 2), location); return token::STRING;
        }
        if (c == '=' && peekc() == '>') { m_text += (char)getc(); count(); DEFAULT_BUILD(location); return token::BUILTIN_POINTER; }
        if (c == ':' && peekc() == ':') { m_text += (char)getc(); count(); DEFAULT_BUILD(location); return token::NAMESPACE_POINTER; }
        if (c == '@') { count(); DEFAULT_BUILD(location); return token::DECORATOR; }
        if (std::strchr("()[]{}:;,^.*/+-=", c)) { count(); DEFAULT_BUILD(location); return c; }
        count(); BUILD_INVALID(location); return token::UNRECOGNIZED;
    }
}

void piranha::Scanner::comment(void) {
    char c, prev = 0;
    while ((c = yyinput()) != 0) {
        countChar(c);
        if (c == '/' && prev == '*') return;
        prev = c;
    }
    LexerError("Unterminated comment");
}

void piranha::Scanner::count() {
    step();
    for (size_t i = 0; i < m_text.size(); i++) countChar(m_text[i]);
}

void piranha::Scanner::countChar(char c) {
    if (c == '\n') { m_loc->lineEnd++; m_loc->colEnd = 1; }
    else if (c == '\t') m_loc->colEnd += 4;
    else m_loc->colEnd++;
}

void piranha::Scanner::step() {
    m_loc->lineStart = m_loc->lineEnd;
    m_loc->colStart = m_loc->colEnd;
}
