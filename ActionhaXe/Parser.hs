-- Parse the tokens generated by Lexer
-- TODO: function declarations, 
--       expressions, 
--       updating Array parameter type,
--       for 
--       while/do
--       if
--       case

module ActionhaXe.Parser(Semi, BlockItem(..), Signature(..), Arg(..), Ast(..), Package(..), parseTokens) where

import ActionhaXe.Lexer
import ActionhaXe.Prim
import ActionhaXe.Data
import Text.Parsec
import Text.Parsec.Combinator
import Text.Parsec.Perm

emptyctok = ([],[])

program :: AsParser Ast
program = do{ x <- package; a <- getState; return $ Program x a}

package = do{ w <- startWs; p <- kw "package"; i <- optionMaybe(ident); storePackage i;  b <- packageBlock; return $ Package w p i b }

packageBlock = do{ l <- op "{"; enterScope; x <- inPackageBlock; r <- op "}"; exitScope; return $ Block l x r }

inPackageBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- importDecl; i <- inPackageBlock; return $ [x] ++ i})
      <|> try(do{ x <- classDecl; i <- inBlock; return $ [x] ++ i})
      <|> try(do{ x <- anytok; i <- inPackageBlock; return $ [(Tok x)] ++ i})

classBlock = do{ l <- op "{"; enterScope; x <- inClassBlock; r <- op "}"; exitScope; return $ Block l x r }

inClassBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- methodDecl; i <- inClassBlock; return $ [x] ++ i})
      <|> try(do{ x <- memberVarDecl; i <- inClassBlock; return $ [x] ++ i})
      <|> try(do{ x <- reg; i <- inClassBlock; return $ [(Regex x)] ++ i})
      <|> try(do{ x <- anytok; i <- inClassBlock; return $ [(Tok x)] ++ i})

methodBlock = do{ l <- op "{"; enterScope; x <- inMethodBlock; r <- op "}"; exitScope; return $ Block l x r }

inMethodBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ b <- block; i <- inMethodBlock; return $ [b] ++ i })
      <|> try(do{ x <- varDecl; i <- inMethodBlock; return $ [x] ++ i})
      <|> try(do{ x <- reg; i <- inMethodBlock; return $ [(Regex x)] ++ i})
      <|> try(do{ x <- anytok; i <- inMethodBlock; return $ [(Tok x)] ++ i})

block = do{ l <- op "{"; enterScope; x <- inBlock; r <- op "}"; exitScope; return $ Block l x r }

inBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ b <- block; i <- inBlock; return $ [b] ++ i })
      <|> try(do{ x <- varDecl; i <- inBlock; return $ [x] ++ i})
      <|> try(do{ x <- reg; i <- inBlock; return $ [(Regex x)] ++ i})
      <|> try(do{ x <- anytok; i <- inBlock; return $ [(Tok x)] ++ i})

importDecl = do{ k <- kw "import"; s <- sident; o <- maybeSemi; return $ ImportDecl k s o}

classDecl = do{ a <- classAttributes; k <- kw "class"; i <- ident; e <- optionMaybe(classExtends); im <- optionMaybe(classImplements); storeClass i; b <- classBlock; return $ ClassDecl a k i e im b}

classAttributes = permute $ list <$?> (emptyctok, (try (kw "public") <|> (kw "internal"))) <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "dynamic")
    where list v s d = filter (\a -> fst a /= []) [v,s,d]

classExtends = do{ k <- kw "extends"; s <- nident; return $ k:[s]}

classImplements = do{ k <- kw "implements"; s <- sepByCI1 nident (op ","); return $ k:s}

methodDecl = do{ attr <- methodAttributes; k <- kw "function"; acc <- optionMaybe( try(kw "get") <|> (kw "set")); n <- nident; enterScope; sig <- signature; b <- methodBlock; exitScope; storeMethod n; return $ MethodDecl attr k acc n sig b}

methodAttributes = permute $ list <$?> (emptyctok, (try (kw "public") <|> try (kw "private") <|> (kw "protected"))) <|?> (emptyctok, ident) <|?> (emptyctok, kw "override") <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "final") <|?> (emptyctok, kw "native")
    where list v o s f n ns = filter (\a -> fst a /= []) [v,ns,o,s,f,n]

signature = do{ lp <- op "("; a <- sigargs; rp <- op ")"; ret <- optionMaybe ( do{ o <- op ":"; r <- datatype; return (o, r)}); return $ Signature lp a rp ret} -- missing return type means constructor

sigargs = do{ s <- many sigarg; return s}
sigarg = try(do{ a <- ident; o <- op ":"; t <- datatype; d <- optionMaybe( do{ o' <- op "="; a <- defval; return $ [o']++a}); c <- optionMaybe(op ","); storeVar a t; return $ Arg a o t d c})
     <|> do{ d <- count 3 (op "."); i <- ident; storeVar i AsTypeRest; return $ RestArg d i }

defval = do{ x <- manyTill defval' (try (lookAhead (op ",")) <|> lookAhead(op ")")); return x }

defval' = try( do{ x <- kw "null"; return x})
      <|> try( do{ x <- kw "true"; return x})
      <|> try( do{ x <- kw "false"; return x})
      <|> try( do{ x <- ident; return x})
      <|> try( do{ x <- str; return x})
      <|> do{ x <- num; return x}

varDecl = do{ ns <- optionMaybe(varAttributes); k <- try(kw "var") <|> (kw "const"); n <- nident; c <- op ":"; dt <- datatype; s <- maybeSemi; storeVar n dt; return $ VarDecl ns k n c dt s}
varAttributes = permute $ list <$?> (emptyctok, (try (kw "public") <|> try (kw "private") <|> (kw "protected"))) <|?> (emptyctok, ident) <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "native")
    where list v ns s n = filter (\a -> fst a /= []) [v,ns,s,n]

memberVarDecl = do{ ns <- optionMaybe(varAttributes)
                  ; k <- try(kw "var") <|> (kw "const")
                  ; n <- nident
                  ; c <- op ":"
                  ; dt <- datatype
                  ; s <- maybeSemi
                  ; i <- optionMaybe( do{ e <- op "="; d <- defval'; return [e, d]})
--                  ; storeVar n dt
                  ; return $ MemberVarDecl ns k n c dt i s}

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
       <|> do{ i <- ident; return $ AsTypeUser i}

parseTokens :: String -> [Token] -> Either ParseError Ast
parseTokens filename ts = runParser program initState filename ts
