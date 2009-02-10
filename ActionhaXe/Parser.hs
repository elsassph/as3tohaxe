{-
    as3tohaxe - An Actionscript 3 to haXe source file translator
    Copyright (C) 2008 Don-Duong Quach

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
-}
-- Parse the tokens generated by Lexer
-- TODO:
--       updating Array parameter type,
--       for 
--       while/do
--       if
--       case

module ActionhaXe.Parser(parseTokens) where

import ActionhaXe.Lexer
import ActionhaXe.Prim
import ActionhaXe.Data
import Text.Parsec
import Text.Parsec.Combinator
import Text.Parsec.Perm
import Text.Parsec.Expr

emptyctok = ([],[])

parseTokens :: String -> [Token] -> Either ParseError Ast
parseTokens fname ts = do let st = initState
                          let st' = st{filename = fname}
                          runParser program st' fname ts

program :: AsParser Ast
program = try(do{ x <- package; a <-getState; return $ AS3Program x a})
       <|>    do{ x <- directives; a <- getState; return $ AS3Directives x a }
         

package = do{ ws <- startWs; p <- kw "package"; i <- optionMaybe(ident); storePackage i;  b <- packageBlock; return $ Package ws p i b }

packageBlock = do{ l <- op "{"; enterScope; x <- inPackageBlock; r <- op "}"; exitScope; return $ Block l x r }

inPackageBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- metadata; i <- inPackageBlock; return $ [x] ++ i})
      <|> try(do{ x <- importDecl; i <- inPackageBlock; return $ [x] ++ i})
      <|> try(do{ x <- classDecl; i <- inPackageBlock; return $ [x] ++ i})
      <|> try(do{ x <- interface; i <- inPackageBlock; return $ [x] ++ i})
      <|>    (do{ x <- anytok; i <- inPackageBlock; return $ [(Tok x)] ++ i})

directives = do{ ws <- startWs; x <- many1 (choice[metadata, importDecl, methodDecl, varS, do{ x <- anytok; return $ Tok x}]); return $ (Tok ws):x}

classBlock = do{ l <- op "{"; enterScope; x <- inClassBlock; r <- op "}"; exitScope; return $ Block l x r }

inClassBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- metadata; i <- inClassBlock; return $ [x] ++ i})
      <|> try(do{ x <- methodDecl; i <- inClassBlock; return $ [x] ++ i})
      <|> try(do{ x <- varS; i <- inClassBlock; return $ [x] ++ i})
      <|>    (do{ x <- anytok; i <- inClassBlock; return $ [(Tok x)] ++ i})

interfaceBlock = do{ l <- op "{"; enterScope; x <- inInterfaceBlock; r <- op "}"; exitScope; return $ Block l x r }

inInterfaceBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- metadata; i <- inInterfaceBlock; return $ [x] ++ i})
      <|> try(do{ x <- methodDecl; i <- inInterfaceBlock; return $ [x] ++ i})
      <|>    (do{ x <- anytok; i <- inInterfaceBlock; return $ [(Tok x)] ++ i})

funcBlock = do{ l <- op "{"; enterScope; x <- inMethodBlock; r <- op "}"; exitScope; return $ Block l x r }

inMethodBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- metadata; i <- inMethodBlock; return $ [x] ++ i})
      <|> try(do{ x <- expr; i <- inMethodBlock; return $ [x] ++ i})
      <|> try(do{ b <- block; i <- inMethodBlock; return $ [b] ++ i })
      <|> try(do{ x <- statement; i <- inMethodBlock; return $ [x]++i})
      <|>    (do{ x <- anytok; i <- inMethodBlock; return $ [(Tok x)] ++ i})

block = do{ l <- op "{"; enterScope; x <- inBlock; r <- op "}"; exitScope; return $ Block l x r }

inBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- metadata; i <- inBlock; return $ [x] ++ i})
      <|> try(do{ x <- expr; i <- inBlock; return $ [x] ++ i})
      <|> try(do{ b <- block; i <- inBlock; return $ [b] ++ i })
      <|> try(do{ x <- statement; i <- inBlock; return $ [x]++i})
      <|>    (do{ x <- anytok; i <- inBlock; return $ [(Tok x)] ++ i})

metadata = do{ l <- op "["
             ;   try(do{ t <- mid "SWF";  
                       ; lp <- op "("
                       ; m <- metadataSwf
                       ; rp <- op ")"
                       ; r <- op "]"
                       ; return $ Metadata $ MDSwf m
                       }
                    )
             <|> try(do{ t <- choice[mid "ArrayElementType"
                                    , mid "Bindable"
                                    , mid "DefaultProperty" , mid "Deprecated"
                                    , mid "Effect" , mid "Embed" , mid "Event" , mid "Exclude" , mid "ExcludeClass"
                                    , mid "IconFile" , mid "Inspectable" , mid "InstanceType"
                                    , mid "NonCommittingChangeEvent"
                                    , mid "RemoteClass"
                                    , mid "Style"
                                    , mid "Transient"
                                    ]
                       ; x <- manyTill anytok (lookAhead(op "]"))
                       ; r <- op "]"
                       ; return $ Metadata $ MD l t x r
                       }
                    )
             }

metadataSwf = 
    permute $ mlist <$?> (missing, item "width") <|?> (missing, item "height") <|?> (missing, item "backgroundColor") <|?> (missing, item "frameRate")
        where mlist w h b f = filter (\a -> (fst a) /= emptyctok) [w, h, b, f]
              item i = do{ x <- mid i; op "="; s <- str; optionMaybe (op ","); return (x, s)}
              missing = (emptyctok, emptyctok)

importDecl = do{ k <- kw "import"; s <- sident; o <- maybeSemi; return $ ImportDecl k s o}

interface = do{ a <- classAttributes; k <- kw "interface"; i <- ident; e <- optionMaybe(interfaceExtends); b <- classBlock; return $ Interface a k i e b}

interfaceExtends = do{ k <- kw "extends"; s <- many1 (do{n <- nident; c <- optionMaybe (op ","); return (n,c)}); return $ (k,s) } 

classDecl = do{ a <- classAttributes; k <- kw "class"; i <- ident; e <- optionMaybe(classExtends); im <- optionMaybe(classImplements); storeClass i; b <- classBlock; return $ ClassDecl a k i e im b}

classAttributes = permute $ list <$?> (emptyctok, (choice[kw "public", kw "internal"])) <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "dynamic")
    where list v s d = filter (\a -> fst a /= []) [v,s,d]

classExtends = do{ k <- kw "extends"; s <- nident; return $ (k, s)}

classImplements = do{ k <- kw "implements"; s <- many1 (do{n <- nident; c <- optionMaybe (op ","); return (n,c)}); return $ (k,s) } 

methodDecl = try(do{ attr <- methodAttributes
               ; k <- kw "function"
               ; acc <- optionMaybe(try(do{ k <- (kw "get" <|> kw "set"); try(do{ o <- op "("; unexpected (showb o)} <|> return ()); return k}))
               ; n <- choice[ nident, kw "each", kw "get", kw "set", kw "include", kw "override"]
               ; enterScope
               ; sig <- signature
               ; b <- optionMaybe funcBlock
               ; exitScope
               ; storeProperty n acc sig
               ; return $ MethodDecl attr k acc n sig b})

methodAttributes = permute $ list <$?> (emptyctok, (choice[kw "public", kw "private", kw "protected", kw "internal"])) <|?> (emptyctok, ident) <|?> (emptyctok, kw "internal") <|?> (emptyctok, kw "override") <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "final") <|?> (emptyctok, kw "native")
    where list v ns i o s f n = filter (\a -> fst a /= []) [v,ns,i,o,s,f,n]

signature = do{ lp <- op "("; a <- sigargs; rp <- op ")"; ret <- optionMaybe ( do{ o <- op ":"; r <- datatype; return (o, r)}); return $ Signature lp a rp ret} -- missing return type means constructor

sigargs = do{ s <- many sigarg; return s}
sigarg = try(do{ a <- idn; o <- op ":"; 
                 try(do{ t <- datatype; d <- optionMaybe( do{ o <- op "="; a <- assignE; return $ (o, a)}); c <- optionMaybe(op ","); storeVar a t; return $ Arg a o t d c})
             <|> try(do{ d <- op "*=" -- special case where no space between *= is parsed as an operator
                       ; let (d', eq) = extractDynamicType d
                       ; e <- assignE;
                       ; c <- optionMaybe(op ",")
                       ; let t = AsType d'
                       ; storeVar a t;
                       ; return $ Arg a o t (Just (eq, e)) c
                       })
             })
     <|> do{ d <- op "..."; i <- idn; t <- optionMaybe (do{ o <- op ":"; t <- datatype; return (o, t)}); storeVar i AsTypeRest; return $ RestArg d i t }

-- extractDynamicType used by sigarg to split TokenOp *= into the * datatype and = for assignment
extractDynamicType ([t], s) = (([dt], []), ([eq], s))
    where sourceName = tokenSource t
          sourceLine = tokenLine t
          sourceCol  = tokenCol t
          dt = (TPos sourceName sourceLine sourceCol, TokenOp "*")
          eq = (TPos sourceName sourceLine (sourceCol+1), TokenOp "=")
 
varS = try(do{ ns <- varAttributes
             ; k <- choice[kw "var", kw "const"]
             ; v <- varBinding
             ; vs <- many (do{ s <- op ","; v <- varBinding; return (s, v)})
             ; return $ VarS ns k v vs 
             }
          )

varAttributes = permute $ list <$?> (emptyctok, (choice[kw "public", kw "private", kw "protected", kw "internal"])) <|?> (emptyctok, ident) <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "native")
    where list v ns s n = filter (\a -> fst a /= []) [v,ns,s,n]

varBinding = try(do{ n <- idn
                   ; t <- optionMaybe(do{c <- op ":"; dt <- datatype; return (c, dt)})
                   ; i <- optionMaybe (do{ o <- op "="; e <- assignE; return $ (o, e)})
                   ; return $ VarBinding n t i
                   }
                )


datatype = try(do{ t <- kw "void";      return $ AsType t})
       <|> try(do{ t <- mid "int";      return $ AsType t})
       <|> try(do{ t <- mid "uint";     return $ AsType t})
       <|> try(do{ t <- mid "Number";   return $ AsType t})
       <|> try(do{ t <- mid "Boolean";  return $ AsType t})
       <|> try(do{ t <- mid "String";   return $ AsType t})
       <|> try(do{ t <- mid "Object";   return $ AsType t})
       <|> try(do{ t <- op "*";         return $ AsType t})
       <|> try(do{ t <- mid "Array";    return $ AsType t})
       <|> try(do{ t <- mid "Function"; return $ AsType t})
       <|> try(do{ t <- mid "RegExp";   return $ AsType t})
       <|> try(do{ t <- mid "XML";      return $ AsType t})
       <|> try(do{ t <- mid "Class";    return $ AsType t})
-- Vector.<*> new in flash 10
       <|> do{ i <- ident; return $ AsTypeUser i}

primaryE = try(do{ x <- kw "this"; return $ PEThis x})
       <|> try(do{ x <- idn; return $ PEIdent x})
       <|> try(do{ x <- choice[kw "null", kw "true", kw "false", kw "public", kw "private", kw "protected", kw "internal"]; return $ PELit x})
       <|> try(do{ x <- str; return $ PELit x})
       <|> try(do{ x <- num; return $ PELit x})
       <|> try(do{ x <- arrayLit; return $ PEArray x})
       <|> try(do{ x <- objectLit; return $ PEObject x})
--       <|> try(do{ x <- reg; return $ PERegex x})
       <|> try(do{ x <- xml; return $ PEXml x})
       <|> try(do{ x <- funcE; return $ PEFunc x})
       <|> do{ x <- parenE; return $ x} 

arrayLit = try(do{ l <- op "["; e <- elementList; r <- op "]"; return $ ArrayLit l e r})
       <|> do{ l <- op "["; e <- optionMaybe elision; r <- op "]"; return $ ArrayLitC l e r}

elementList = do 
    l <- optionMaybe elision
    e <- assignE
    el <- many (try(do{ c <- elision; p <- assignE; return $ EAE c p}))
    r <- optionMaybe elision
    return $ El l e el r

elision = do{ x <- many1 (op ","); return $ Elision x}

objectLit = do{ l <- op "{"; x <- optionMaybe propertyNameAndValueList; r <- op "}"; return $ ObjectLit l x r}

propertyNameAndValueList = do{ x <- many1 (do{ p <- propertyName; c <- op ":"; e <- assignE; s <- optionMaybe (op ","); return (p, c, e, s)}); return $ PropertyList x}

propertyName = do{ x <- choice [ident, str, num]; return x}

funcE = do{ f <- kw "function"; i <- optionMaybe ident; enterScope; s <- signature; b <- funcBlock; exitScope; return $ FuncE f i s b}

parenE = do{ l <- op "("; e <- listE; r <- op ")"; return $ PEParens l e r}

listE = do{ e <- many1 (do{x <- assignE; c <- optionMaybe (op ","); return (x, c)}); return $ ListE e}

listENoIn = do{ e <- many1 (do{x <- assignENoIn; c <- optionMaybe (op ","); return (x, c)}); return $ ListE e}

postFixE = try(do{ x <- fullPostFixE; o <- postFixUp; return $ PFFull x o})
        <|> do{ x <- shortNewE; o <- postFixUp; return $ PFShortNew x o}
    where postFixUp = optionMaybe (do{ o <- choice [op "++", op "--"]; return o})

fullPostFixE = try(do{ x <- primaryE; s <- many fullPostFixSubE; return $ FPFPrimary x s})
           <|> try(do{ x <- fullNewE; s <- many fullPostFixSubE; return $ FPFFullNew x s})
           <|> (do{ x <- superE; p <- propertyOp; s <- many fullPostFixSubE; return $ FPFSuper x p s})

fullPostFixSubE = try(do{ p <- propertyOp; return $ FPSProperty p})
              <|> try(do{ a <- args; return $ FPSArgs a})  -- call expression
              <|> do{ q <- queryOp; return $ FPSQuery q}

fullNewE = do{ k <- kw "new"; e <- fullNewSubE; a <- args; return $ FN k e a}

fullNewSubE = try(do{ e <- fullNewE; return e})
          <|> try(do{ e <- primaryE; p <- many propertyOp; return $ FNPrimary e p})
          <|> do{ e <- superE; p <- many1 propertyOp; return $ FNSuper e p}

shortNewE = do{ k <- kw "new"; s <- shortNewSubE; return $ SN k s}

shortNewSubE = try(do{ e <- fullNewSubE; return $ SNSFull e})
           <|> do{ e <- shortNewE; return $ SNSShort e}

superE = do{ k <- kw "super"; p <- optionMaybe args; return $ SuperE k p}

args = do{ l <- op "("; e <- optionMaybe listE; r <- op ")"; return $ Arguments l e r}

propertyOp = try(do{ o <- op "."; n <- idn; return $ PropertyOp o n})
         <|> do{ l <- op "["; e <- listE; r <- op "]"; return $ PropertyB l e r}

queryOp = try(do{ o <- op ".."; n <- nident; return $ QueryOpDD o n})
      <|> do{ o <- op "."; l <- op "("; e <- listE; r <- op ")"; return $ QueryOpD o l e r}

unaryE = try(do{ k <- kw "delete"; p <- postFixE; return $ UEDelete k p})
     <|> try(do{ k <- kw "void"; p <- postFixE; return $ UEVoid k p})
     <|> try(do{ k <- kw "typeof"; p <- postFixE; return $ UETypeof k p})
     <|> try(do{ o <- op "++"; p <- postFixE; return $ UEInc o p})
     <|> try(do{ o <- op "--"; p <- postFixE; return $ UEDec o p})
     <|> try(do{ o <- op "+"; p <- unaryE; return $ UEPlus o p})
     <|> try(do{ o <- op "-"; p <- unaryE; return $ UEMinus o p})
     <|> try(do{ o <- op "~"; p <- unaryE; return $ UEBitNot o p})
     <|> try(do{ o <- op "!"; p <- unaryE; return $ UENot o p})
     <|> do{ p <- postFixE; return $ UEPrimary p }

aeUnary = do{ x <- unaryE; return $ AEUnary x}

aritE = buildExpressionParser (aritOpTable True) aeUnary

aritENoIn = buildExpressionParser (aritOpTable False) aeUnary

aritOpTable allowIn =
    [
     [o "*", o "/", o "%"],                     -- multiplicative
     [o "+", o "-"],                             -- additive
     [o "<<", o ">>", o ">>>"],                 -- shift
     [o "<", o ">", o "<=", o ">="] 
         ++ (if allowIn == True then [ok "in"] else []) 
         ++ [ ok "instanceof", ok "is", ok "as"],   -- relational
     [o "==", o "!=", o "===", o "!=="],       -- equality
     [o "&"], [o "^"], [o "|"],                 -- bitwise
     [o "&&"], [o "||"]                          -- logical
    ]
    where o opr = Infix (do{ o' <- op opr; return (\x y -> AEBinary o' x y)}) AssocLeft
          ok kop = Infix (do{ k <- kw kop; return (\x y -> AEBinary k x y)}) AssocLeft

regE = do{ l <- op "/"; x <- manyTill anytok (try(lookAhead(op "/"))); r <- op "/"; o <- optionMaybe idn; return $ RegE l x r o}

condE = try(do{ r <- regE; return $ CondRE r})
    <|> do{ e <- aritE; o <- optionMaybe (do{ q <- op "?"; e1 <- assignE; c <- op ":"; e2 <- assignE; return $ (q, e1, c, e2)}); return $ CondE e o}

condENoIn = try(do{ r <- regE; return $ CondRE r})
        <|> do{ e <- aritENoIn; o <- optionMaybe (do{ q <- op "?"; e1 <- assignENoIn; c <- op ":"; e2 <- assignENoIn; return $ (q, e1, c, e2)}); return $ CondE e o}

nonAssignE = do{ e <- aritE; o <- optionMaybe (do{ q <- op "?"; e1 <- nonAssignE; c <- op ":"; e2 <- nonAssignE; return $ (q, e1, c, e2)}); return $ NAssignE e o}

nonAssignENoIn = do{ e <- aritENoIn; o <- optionMaybe (do{ q <- op "?"; e1 <- nonAssignENoIn; c <- op ":"; e2 <- nonAssignENoIn; return $ (q, e1, c, e2)}); return $ NAssignE e o}

typeE = nonAssignE

typeENoIn = nonAssignENoIn

assignE = try(do{ p <- postFixE; 
                          try(do{o <- choice [op "&&=", op "^^=", op "||="]; a <- assignE; return $ ALogical p o a})
                      <|> try(do{o <- choice [op "*=", op "/=", op "%=", op "+=", op "-=", op "<<=", op ">>=", op ">>>=", op "&=", op "^=", op "|="]; a <- assignE; return $ ACompound p o a})
                      <|>     do{o <- op "="; a <- assignE; return $ AAssign p o a}
                }
             )
      <|> do{ e <- condE; return $ ACond e}

assignENoIn = try(do{ p <- postFixE; 
                          try(do{o <- choice [op "&&=", op "^^=", op "||="]; a <- assignENoIn; return $ ALogical p o a}) 
                      <|> try(do{o <- choice [op "*=", op "/=", op "%=", op "+=", op "-=", op "<<=", op ">>=", op ">>>=", op "&=", op "^=", op "|="]; a <- assignENoIn; return $ ACompound p o a})
                      <|>     do{o <- op "="; a <- assignENoIn; return $ AAssign p o a}
                    }
                 )
          <|> do{ e <- condE; return $ ACond e}

expr = do{ x <- assignE; return $ Expr x}

exprNoIn = do{ x <- assignENoIn; return $ Expr x}

statement = try(do{ x <- varS; return x})
        <|> try(do{ x <- forS; return x})
        <|>     do{ x <- forInS; return x}

forS = do k <- kw "for"
          l <- op "("
          init <- optionMaybe forInit
          s <- op ";"
          e <- optionMaybe listE
          s1 <- op ";"
          e1 <- optionMaybe listE
          r <- op ")"
          b <- block
          return $ ForS k l init s e s1 e1 r b
    where forInit = try(do{ l <- listENoIn; return $ FIListE l})
                <|>     do{ x <- varS; return $ FIVarS x}

forInS = do k <- kw "for"
            me <- optionMaybe (kw "each")
            l <- op "("
            fb <- fbind
            i <- kw "in"
            e <- listE
            r <- op ")"
            b <- block
            return $ ForInS k me l fb i e r b
    where fbind = try(do{ p <- postFixE; return $ FIBPostE p})
              <|>     do{ v <- choice [kw "var", kw "const"]; b <- varBinding; return $ FIBVar v b}
