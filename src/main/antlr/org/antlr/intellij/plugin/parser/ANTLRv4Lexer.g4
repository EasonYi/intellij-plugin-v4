/*
 * [The "BSD license"]
 *  Copyright (c) 2014 Terence Parr
 *  Copyright (c) 2014 Sam Harwell
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *  1. Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *  3. The name of the author may not be used to endorse or promote products
 *     derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 *  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 *  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 *  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 *  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 *  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/** A grammar for ANTLR v4 tokens */
lexer grammar ANTLRv4Lexer;

tokens {
	TOKEN_REF,
	RULE_REF,
	LEXER_CHAR_SET
}

@members {
    // Generic type for OPTIONS, TOKENS and CHANNELS
    private int PREQUEL_CONSTRUCT = -10;

	/** Track whether we are inside of a rule and whether it is lexical parser.
	 *  _currentRuleType==Token.INVALID_TYPE means that we are outside of a rule.
	 *  At the first sign of a rule name reference and _currentRuleType==invalid,
	 *  we can assume that we are starting a parser rule. Similarly, seeing
	 *  a token reference when not already in rule means starting a token
	 *  rule. The terminating ';' of a rule, flips this back to invalid type.
	 *
	 *  This is not perfect logic but works. For example, "grammar T;" means
	 *  that we start and stop a lexical rule for the "T;". Dangerous but works.
	 *
	 *  The whole point of this state information is to distinguish
	 *  between [..arg actions..] and [charsets]. Char sets can only occur in
	 *  lexical rules and arg actions cannot occur.
	 */
	private int _currentRuleType = Token.INVALID_TYPE;

	public int getCurrentRuleType() {
		return _currentRuleType;
	}

	public void setCurrentRuleType(int ruleType) {
		this._currentRuleType = ruleType;
	}

	protected void handleBeginArgument() {
		if (inLexerRule()) {
			pushMode(LexerCharSet);
			more();
		}
		else {
			pushMode(Argument);
		}
	}

	protected void handleEndArgument() {
		popMode();
		if (_modeStack.size() > 0) {
			setType(ARGUMENT_CONTENT);
		}
	}

	protected void handleEndAction() {
		popMode();
		if (_modeStack.size() > 0) {
			setType(ACTION_CONTENT);
		}
	}

	@Override
	public Token emit() {
	    if ((_type == OPTIONS || _type == TOKENS || _type == CHANNELS)
	            && _currentRuleType == Token.INVALID_TYPE) { // enter prequel construct ending with an RBRACE
	        _currentRuleType = PREQUEL_CONSTRUCT;
	    }
	    else if (_type == RBRACE && _currentRuleType == PREQUEL_CONSTRUCT) { // exit prequel construct
	        _currentRuleType = Token.INVALID_TYPE;
	    }
        else if (_type == AT && _currentRuleType == Token.INVALID_TYPE) { // enter action
            _currentRuleType = AT;
        }
        else if (_type == END_ACTION && _currentRuleType == AT) { // exit action
            _currentRuleType = Token.INVALID_TYPE;
        }
	    else if (_type == ID) {
			String firstChar = _input.getText(Interval.of(_tokenStartCharIndex, _tokenStartCharIndex));
			if (Character.isUpperCase(firstChar.charAt(0))) {
				_type = TOKEN_REF;
			} else {
				_type = RULE_REF;
			}

			if (_currentRuleType == Token.INVALID_TYPE) { // if outside of rule def
				_currentRuleType = _type;                 // set to inside lexer or parser rule
			}
		}
		else if (_type == SEMI) {                  // exit rule def
			_currentRuleType = Token.INVALID_TYPE;
		}

		return super.emit();
	}

	private boolean inLexerRule() {
		return _currentRuleType == TOKEN_REF;
	}
	private boolean inParserRule() { // not used, but added for clarity
		return _currentRuleType == RULE_REF;
	}

	/** Override nextToken so we can alter how it handles token errors.
	 *  Instead of looking for a new (valid) token, it should return an
	 *  invalid token. Changed "if ( _type ==SKIP )" part only from 4.7.
	 */
	@Override
	public Token nextToken() {
		if (_input == null) {
			throw new IllegalStateException("nextToken requires a non-null input stream.");
		}

		// Mark start location in char stream so unbuffered streams are
		// guaranteed at least have text of current token
		int tokenStartMarker = _input.mark();
		try{
			outer:
			while (true) {
				if (_hitEOF) {
					emitEOF();
					return _token;
				}

				_token = null;
				_channel = Token.DEFAULT_CHANNEL;
				_tokenStartCharIndex = _input.index();
				_tokenStartCharPositionInLine = getInterpreter().getCharPositionInLine();
				_tokenStartLine = getInterpreter().getLine();
				_text = null;
				do {
					_type = Token.INVALID_TYPE;
//				System.out.println("nextToken line "+tokenStartLine+" at "+((char)input.LA(1))+
//								   " in mode "+mode+
//								   " at index "+input.index());
					int ttype;
					try {
						ttype = getInterpreter().match(_input, _mode);
					}
					catch (LexerNoViableAltException e) {
						notifyListeners(e);		// report error
						recover(e);
						ttype = SKIP;
					}
					if ( _input.LA(1)==IntStream.EOF ) {
						_hitEOF = true;
					}
					if ( _type == Token.INVALID_TYPE ) _type = ttype;
					if ( _type ==SKIP ) {
						_type = Token.INVALID_TYPE;
						emit();
						return _token; // return a single bad token for this unmatched input
//						continue outer;
					}
				} while ( _type ==MORE );
				if ( _token == null ) emit();
				return _token;
			}
		}
		finally {
			// make sure we release marker after match or
			// unbuffered char stream will keep buffering
			_input.release(tokenStartMarker);
		}
	}
}

DOC_COMMENT
	:	'/**' .*? ('*/' | EOF)
	;

BLOCK_COMMENT
	:	'/*' .*? ('*/' | EOF)  -> channel(HIDDEN)
	;

LINE_COMMENT
	:	'//' ~[\r\n]*  -> channel(HIDDEN)
	;

// -------------------------
// Arguments
//
// Certain argument lists, such as those specifying call parameters
// to a rule invocation, or input parameters to a rule specification
// are contained within square brackets.
BEGIN_ARGUMENT
   : '['
   { handleBeginArgument(); }
   ;

// -------------------------
// Actions
BEGIN_ACTION
   : '{' -> pushMode (Action)
;

// OPTIONS and TOKENS must also consume the opening brace that captures
// their option block, as this is the easiest way to parse it separate
// to an ACTION block, despite it using the same {} delimiters.
//
OPTIONS      : 'options'  [ \t\f\n\r]* '{'  ;
TOKENS		 : 'tokens'   [ \t\f\n\r]* '{'  ;
CHANNELS	 : 'channels' [ \t\f\n\r]* '{'  ;

IMPORT       : 'import'               ;
FRAGMENT     : 'fragment'             ;
LEXER        : 'lexer'                ;
PARSER       : 'parser'               ;
GRAMMAR      : 'grammar'              ;
PROTECTED    : 'protected'            ;
PUBLIC       : 'public'               ;
PRIVATE      : 'private'              ;
RETURNS      : 'returns'              ;
LOCALS       : 'locals'               ;
THROWS       : 'throws'               ;
CATCH        : 'catch'                ;
FINALLY      : 'finally'              ;
MODE         : 'mode'                 ;

COLON        : ':'                    ;
COLONCOLON   : '::'                   ;
COMMA        : ','                    ;
SEMI         : ';'                    ;
LPAREN       : '('                    ;
RPAREN       : ')'                    ;
RARROW       : '->'                   ;
LT           : '<'                    ;
GT           : '>'                    ;
ASSIGN       : '='                    ;
QUESTION     : '?'                    ;
STAR         : '*'                    ;
PLUS         : '+'                    ;
PLUS_ASSIGN  : '+='                   ;
OR           : '|'                    ;
DOLLAR       : '$'                    ;
DOT		     : '.'                    ;
RANGE        : '..'                   ;
AT           : '@'                    ;
POUND        : '#'                    ;
NOT          : '~'                    ;
RBRACE       : '}'                    ;

/** Allow unicode rule/token names */
ID	:	NameStartChar NameChar*;

fragment
NameChar
	:   NameStartChar
	|   '0'..'9'
	|   '_'
	|   '\u00B7'
	|   '\u0300'..'\u036F'
	|   '\u203F'..'\u2040'
	;

fragment
NameStartChar
	:   'A'..'Z'
	|   'a'..'z'
	|   '\u00C0'..'\u00D6'
	|   '\u00D8'..'\u00F6'
	|   '\u00F8'..'\u02FF'
	|   '\u0370'..'\u037D'
	|   '\u037F'..'\u1FFF'
	|   '\u200C'..'\u200D'
	|   '\u2070'..'\u218F'
	|   '\u2C00'..'\u2FEF'
	|   '\u3001'..'\uD7FF'
	|   '\uF900'..'\uFDCF'
	|   '\uFDF0'..'\uFFFD'
	; // ignores | ['\u10000-'\uEFFFF] ;

INT	: [0-9]+
	;

// ANTLR makes no distinction between a single character literal and a
// multi-character string. All literals are single quote delimited and
// may contain unicode escape sequences of the form \uxxxx, where x
// is a valid hexadecimal number (as per Java basically).
STRING_LITERAL
	:  '\'' (ESC_SEQ | ~['\r\n\\])* '\''
	;

UNTERMINATED_STRING_LITERAL
	:  '\'' (ESC_SEQ | ~['\r\n\\])*
	;

fragment DOUBLE_QUOTE_LITERAL
   : '"' (ESC_SEQ | ~ ["\r\n\\])* '"'
   ;

// Any kind of escaped character that we can embed within ANTLR
// literal strings.
fragment
ESC_SEQ
	:	'\\'
		(	// The standard escaped character set such as tab, newline, etc.
			[btnfr'\\]
		|	// A Java style Unicode escape sequence
			UNICODE_ESC
		|	// A Swift/Hack style Unicode escape sequence
		 	UNICODE_EXTENDED_ESC
		|	// Invalid escape
			.
		|	// Invalid escape at end of file
			EOF
		)
	;

fragment
UNICODE_ESC
    :   'u' HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT
    ;

fragment
UNICODE_EXTENDED_ESC
    :   'u{'
    	HEX_DIGIT // from 1 to 6 digits
		(	HEX_DIGIT
			(	HEX_DIGIT
				(	HEX_DIGIT
					(	HEX_DIGIT
						HEX_DIGIT?
					)?
				)?
			)?
		)?
    	'}'
    ;

fragment
HEX_DIGIT : [0-9a-fA-F]	;

WS  :	[ \t\r\n\f]+ -> channel(HIDDEN)	;

// -----------------
// Illegal Character
//
// This is an illegal character trap which is always the last rule in the
// lexer specification. It matches a single character of any value and being
// the last rule in the file will match when no other rule knows what to do
// about the character. It is reported as an error but is not passed on to the
// parser. This means that the parser to deal with the gramamr file anyway
// but we will not try to analyse or code generate from a file with lexical
// errors.
//
ERRCHAR
	:	.	-> channel(HIDDEN)
	;

mode Argument;
    // E.g., [int x, List<String> a[]]
    NESTED_ARGUMENT
       : '[' -> type (ARGUMENT_CONTENT) , pushMode (Argument)
       ;

    ARGUMENT_ESCAPE
       : ESC_SEQ -> type (ARGUMENT_CONTENT)
       ;

    ARGUMENT_STRING_LITERAL
       : DOUBLE_QUOTE_LITERAL -> type (ARGUMENT_CONTENT)
       ;

    ARGUMENT_CHAR_LITERAL
       : STRING_LITERAL -> type (ARGUMENT_CONTENT)
       ;

    END_ARGUMENT
       : ']'
       { handleEndArgument(); }
       ;
       // added this to return non-EOF token type here. EOF does something weird

    UNTERMINATED_ARGUMENT
       : EOF -> popMode
       ;

    ARGUMENT_CONTENT
       : .
       ;

// -------------------------
// Actions
//
// Many language targets use {} as block delimiters and so we
// must recursively match {} delimited blocks to balance the
// braces. Additionally, we must make some assumptions about
// literal string representation in the target language. We assume
// that they are delimited by ' or " and so consume these
// in their own alts so as not to inadvertantly match {}.
mode Action;
    NESTED_ACTION
       : '{' -> type (ACTION_CONTENT) , pushMode (Action)
       ;

    ACTION_ESCAPE
       : ESC_SEQ -> type (ACTION_CONTENT)
       ;

    ACTION_STRING_LITERAL
       : DOUBLE_QUOTE_LITERAL -> type (ACTION_CONTENT)
       ;

    ACTION_CHAR_LITERAL
       : STRING_LITERAL -> type (ACTION_CONTENT)
       ;

    ACTION_DOC_COMMENT
       : DOC_COMMENT -> type (ACTION_CONTENT)
       ;

    ACTION_BLOCK_COMMENT
       : BLOCK_COMMENT -> type (ACTION_CONTENT)
       ;

    ACTION_LINE_COMMENT
       : LINE_COMMENT -> type (ACTION_CONTENT)
       ;

    END_ACTION
       : '}'
       { handleEndAction(); }
       ;

    UNTERMINATED_ACTION
       : EOF -> popMode
       ;

    ACTION_CONTENT
       : .
    ;

mode LexerCharSet;

	LEXER_CHAR_SET_BODY
		:	(	~[\]\\]
			|	'\\' .
			)
                                        -> more
		;

	LEXER_CHAR_SET
		:   ']'                         -> popMode
		;

	UNTERMINATED_CHAR_SET
		:	EOF							-> popMode
		;

