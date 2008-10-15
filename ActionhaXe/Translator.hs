-- Translate an Actionscript 3 AST to haXe and hxml for Flash 9

module ActionhaXe.Translator where

import ActionhaXe.Lexer
import ActionhaXe.Data
import ActionhaXe.Prim
import ActionhaXe.Parser
import Data.Map (Map)
import qualified Data.Map as Map
import Control.Monad.State
import Data.Foldable (foldlM, foldrM)
import Data.List (intercalate)
import Data.Char (toUpper, isAlphaNum)

-- flags
mainPackage = "mainPackage"
fpackage  = "packageName"
fclass = "className"
fclassAttr = "classAttr"

updateFlag flag val = do st <- get
                         put st{flags = Map.insert flag val (flags st)}

deleteFlag flag = do st <- get
                     put st{flags = Map.delete flag (flags st)}

getFlag :: String -> StateT AsState IO String
getFlag flag = do st <- get
                  mval <- Map.lookup flag $ flags st
                  return mval

insertInitMember output = do st <- get
                             put st{initMembers = (output:(initMembers st))}
                             st' <- get
                             return ()

getMembers = do st <- get
                let ret = reverse $ initMembers st
                put st{initMembers = []}
                return ret

--translateAs3Ast :: Package -> StateT AsState IO String
translateAs3Ast p = do str <- program p
                       return str

maybeEl f i = maybe "" (\m -> f m) i

--program :: Package -> StateT AsState IO String
program (Package w p n b) = do case n of
                                 Just ntok -> do{ updateFlag fpackage $ showd ntok ; x <- packageBlock b; return $ showb w ++ showd p ++" "++ showd ntok ++ ";" ++ showw ntok ++ x}
                                 Nothing   -> do{ updateFlag fpackage mainPackage; x <-packageBlock b; return $ showb w ++ showw p ++ x}

packageBlock (Block l bs r)  = do 
    bi <- foldlM (\s b -> do{ x <- packageBlockItem b; return $ s ++ x} ) "" bs 
    return $ showw l ++ bi

classBlock (Block l bs r)  = do 
    x <- get
    let a = accessors x
    let al = Map.toList a
    let props = foldl (\str (k, (t, g, s)) -> str ++ "public var " ++ k ++ "(" 
                                          ++ (if g then "get"++ [toUpper $ head k] ++ tail k else "null") ++ ", "
                                          ++ (if s then "set"++ [toUpper $ head k] ++ tail k else "null") 
                                          ++ ") : " ++ datatype t ++ ";" ++ showw l) "" al
    bi <-  foldlM (\s b -> do{ x <- classBlockItem b; return $ s ++ x} ) "" bs 
    return $ showb l ++ props ++ bi ++ showb r

block (Block l bs r)  = do 
    bi <-  foldlM (\s b -> do{ x <- blockItem b; return $ s ++ x} ) "" bs 
    return $ showb l ++ bi ++ showb r

constructorBlock (Block l bs r) = do 
    bi <-  foldrM (\b s -> do{ x <- blockItem b; return $ x ++ s} ) "" bs 
    let spacebreak = break (\c -> c == '\n') ( reverse $ showw l)
    let i =  reverse $ fst spacebreak
    let nl = if (snd spacebreak)!!1 == '\r' then "\r\n" else "\n"
    x <- getMembers
    let init = nl++i++ intercalate (nl++i) x
    return $ showb l ++ init ++ nl ++ i ++ bi ++ showb r

packageBlockItem b = 
    do x <- case b of
                Tok t                       -> tok t >>= return
                ImportDecl _ _ _            -> return $ importDecl b
                ClassDecl _ _ _ _ _ _       -> classDecl b >>= return
                _                           -> return ""
       return x

classBlockItem b = 
    do x <- case b of
                Tok t                       -> tok t >>= return
                MethodDecl _ _ _ _ _ _      -> methodDecl b >>= return
                VarS _ _ _                  -> memberVarS b >>= return
                _                           -> return $ show b
       return x

blockItem b = 
    do x <- case b of
                Tok t                       -> tok t >>= return
                Block _ _ _                 -> block b >>= return
                VarS _ _ _                  -> varS b >>= return
                ForS _ _ _ _ _ _ _ _ _      -> forS b >>= return
                Expr _                      -> expr b >>= return
                _                           -> return ""
       return x

tok t = do let x = showb t
           f <- getFlag fpackage
           return x

importDecl (ImportDecl i n s) = foldr (\t s -> showb t ++ s) "" [i,n] ++ maybeEl showb s  -- look up and adjust

classDecl (ClassDecl a c n e i b) = do
    updateFlag fclass $ showd n
    updateFlag fclassAttr $ publicAttr a
    x <- classBlock b
    return $ attr a ++ showb c ++ showb n ++ maybeEl showl e ++ implements i ++ x 
    where publicAttr as = if "public" `elem` map (\a -> showd a) as then "public" else "private"
          attr as = concat $ map (\attr -> case (showd attr) of { "internal" -> "private" ++ showw attr; "public" -> ""; x -> showb attr }) as
          implements is = maybeEl showl is

methodDecl (MethodDecl a f ac n s b) = do 
    packageName <- getFlag fpackage
    className <- getFlag fclass
    classAttr <- getFlag fclassAttr
    if packageName == mainPackage && className == (showd n) && classAttr == "public"
        then do{ x <- maybe (return "") block b; return $ "static " ++ showb f ++ "main() "++ x }
        else if className == (showd n)
                 then do{ x <- maybe (return "") constructorBlock b; return $ attr a ++ showb f ++ "new"++showw n ++ signatureArgs s ++ x }
                 else do{ x <- maybe (return "") block b
                        ; st <- get
                        ; let accMap = accessors st
                        ; (t, _, _) <- Map.lookup (showd n) accMap
                        ; return $ attr a ++ showb f ++ accessor ac n s t ++ x }
    where attr as = concat $ map (\attr -> case (showd attr) of { "internal" -> "private" ++ showw attr; "protected" -> "public" ++ showw attr; x -> showb attr }) as
          accessor ac name s@(Signature l args r ret) t = 
              case ac of
                  Just x -> showd x ++ [toUpper $ head $ showd name] ++ tail (showb name) ++ showb l ++ showArgs args ++ showd r ++ ":" 
                            ++ fst (datatypet t) ++ (case ret of { Just (c, t) -> snd (datatypet t); Nothing -> showw r})
                  Nothing -> showb name ++ signature s

signatureArgs (Signature l args r ret) = showb l ++ showArgs args  ++ showb r

rettype ret = case ret of
                  Just (c, t) -> showb c ++ datatype t
                  Nothing     -> ""

signature (Signature l args r ret) = showb l ++ showArgs args  ++ showb r ++ rettype ret

showArgs as = concat $ map showArg as
    where showArg (Arg n c t md mc) = (case md of{ Just d  -> "?"; Nothing -> ""}) ++ showb n ++ showb c ++ datatype t ++ maybeEl showl md ++ maybeEl showb mc

memberVarS (VarS ns v b) = do 
    if maybe False (\x -> elem "static" (map (\n -> showd n) x )) ns
        then do{ b' <- foldrM (\x s -> do{ x' <- varBinding x False; return $ x' ++ s}) "" b; return $ namespace ns ++ "var" ++ showw v ++ b'}
        else do{ b' <- foldlM (\s x -> do{ x' <- varBinding x True; return $ s ++ x'}) "" b; return $ namespace ns ++ "var" ++ showw v ++ b'}

varS (VarS ns v b) = do{ b' <- foldrM (\x s -> do{ x' <- varBinding x False; return $ x' ++ s}) "" b; return $ namespace ns ++ "var" ++ showw v ++ b'}

varBinding :: VarBinding -> Bool -> StateT AsState IO String
varBinding (VarBinding n c d i s) initMember = 
    do{ i' <- maybe (return "") (\(o, e) -> do{ e' <- assignE e; return $ showb o ++ e'}) i; 
      ; if i' /= "" && initMember
            then do{ insertInitMember $ showb n ++ (if last(showb n) == ' ' then "" else " ") ++ i' ++ ";"; return $ showl [n,c] ++ datatype d ++ maybeEl showb s}
            else return $ showl [n,c] ++ datatype d ++ i' ++ maybeEl showb s
      }

namespace ns = case ns of 
                   Just x -> concat $ map (\n -> (case (showd n) of { "protected" -> "public"; _ -> showd n})  ++ showw n) x
                   Nothing -> ""

datatypet d = span isAlphaNum (datatype d)

datatype d = case d of
                 AsType n -> (case (showd n) of
                                  "void"    -> "Void"
                                  "Boolean" -> "Bool"
                                  "uint"    -> "UInt"
                                  "int"     -> "Int"
                                  "Number"  -> "Float"
                                  "String"  -> "String"
                                  "*"       -> "Dynamic"
                                  "Object"  -> "Dynamic"
                                  "Function"-> "Dynamic"
                                  "Array"   -> "Array<Dynamic>"
                                  "XML"     -> "Xml"
                                  "RegExp"  -> "EReg"
                             ) ++ showw n
                 AsTypeRest -> "Array<Dynamic>"
                 AsTypeUser n -> showb n

primaryE x = case x of
                 PEThis x -> do{ return $ showb x}
                 PEIdent x -> do{ return $ showb x}
                 PELit x -> do{ return $ showb x}
                 PEArray x -> do{ r <- arrayLit x; return r}
                 PEObject x -> do{ r <- objectLit x; return r}
                 PERegex x -> do{ return $ "~" ++ showb x}
                 PEXml x -> do{ return $ "Xml.parse(\""++ showd x ++ "\")" ++ showw x}
                 PEFunc x -> do{ r <- funcE x; return r}
                 PEParens l x r -> do{ v <- listE x; return $ showb l ++ v ++ showd r ++ showw r}

arrayLit (ArrayLitC l x r) = do{ return $ showb l ++ maybe "" elision x ++ showb r }

arrayLit (ArrayLit l x r) = do{ e <- elementList x; return $ showb l ++ e ++ showb r}

elementList (El l e el r) = do{ es <- assignE e; els <- foldrM (\(EAE c p) s -> do{ ps <- assignE p; return $ elision c ++ ps ++ s}) "" el; return $ maybeEl elision l ++ es ++ els ++ maybeEl elision r }

elision (Elision x) = showl x

objectLit (ObjectLit l x r) = do{ p <- maybe (return "") propertyNameAndValueList x; return $ showb l ++ p ++ showb r}

propertyNameAndValueList (PropertyList x) = do
    p <- foldrM (\(p, c, e, s) str -> do{ ex <- assignE e; return $ showb p ++ showb c ++ ex ++ maybe "" showb s ++ str}) "" x
    return p

funcE (FuncE f i s b) = do{ x <- block b; return $ showb f ++ signature s ++ x}

listE (ListE l) = do{ x <- foldrM (\(e, c) s -> do{es <- assignE e; return $ es ++ maybe "" showb c ++ s} ) "" l; return x}

listENoIn = listE

postFixE x = case x of
                 PFFull p o     -> do{ p' <- fullPostFixE p; o' <- postFixUp o; return $ p' ++ o'}
                 PFShortNew p o -> do{ p' <- shortNewE p; o' <- postFixUp o; return $ p' ++ o'}
    where postFixUp o = return $ maybe "" showb o

fullPostFixE x = case x of
                    FPFPrimary p sb  -> do{ e <- primaryE p; sub <- foldsub sb; return $ e ++ sub}
                    FPFFullNew f sb  -> do{ e <- fullNewE f; sub <- foldsub sb; return $ e ++ sub}
                    FPFSuper s p sb  -> do{ e <- superE s; p' <- propertyOp p; sub <- foldsub sb; return $ e ++ p' ++ sub}
    where foldsub sb = foldrM (\a b -> do{c <- fullPostFixSubE a; return $ c ++ b}) "" sb 

fullPostFixSubE x = case x of
                        FPSProperty p -> propertyOp p >>= return
                        FPSArgs     a -> args a >>= return
                        FPSQuery    q -> queryOp q >>= return

fullNewE (FN k e a) = do{ e' <- fullNewSubE e; a' <- args a; return $ showb k ++ e' ++ a'}

fullNewSubE x = case x of
                    FN _ _ _      -> do{ e <- fullNewE x; return e}
                    FNPrimary e p -> do{ e' <- primaryE e; p' <- foldprop p; return $ e' ++ p'}
                    FNSuper e p   -> do{ e' <- superE e; p' <- foldprop p; return $ e' ++ p'}
    where foldprop p = foldrM (\a b -> do{ a' <- propertyOp a; return $ a' ++ b}) "" p

shortNewE (SN k s) = do{ s' <- shortNewSubE s; return $ showb k ++ s'}

shortNewSubE x = case x of
                     SNSFull e  -> fullNewSubE e >>= return
                     SNSShort e -> shortNewE e >>= return

superE (SuperE k p) = do{ p' <- maybe (return "") args p; return $ showb k ++ p'}

propertyOp x = case x of
                   PropertyOp o n  -> return $ showb o ++ showb n
                   PropertyB l e r -> do{ e' <- listE e; return $ showb l ++ e' ++ showb r }

args (Arguments l e r)  = do{ e' <- maybe (return "") listE e; return $ showb l ++ e' ++ showb r}

queryOp x = case x of
                QueryOpDD o n    -> return $ showb o ++ showb n
                QueryOpD o l e r -> do{ e' <- listE e; return $ showb o ++ showb l ++ e' ++ showb r}

unaryE x = case x of
               UEDelete k p   -> do{ p' <- postFixE p; return $ showb k ++ p'}
               UEVoid k p     -> do{ p' <- postFixE p; return $ showb k ++ p'}
               UETypeof k p   -> do{ p' <- postFixE p; return $ showb k ++ p'}
               UEInc o p      -> do{ p' <- postFixE p; return $ showb o ++ p'}
               UEDec o p      -> do{ p' <- postFixE p; return $ showb o ++ p'}
               UEPlus o p     -> do{ p' <- unaryE p; return $ showb o ++ p'}
               UEMinus o p    -> do{ p' <- unaryE p; return $ showb o ++ p'}
               UEBitNot o p   -> do{ p' <- unaryE p; return $ showb o ++ p'}
               UENot o p      -> do{ p' <- unaryE p; return $ showb o ++ p'}
               UEPrimary p    -> postFixE p >>= return

aritE x = case x of
              AEUnary u  -> unaryE u >>= return
              AEBinary _ _ _ -> binaryE x >>= return 

aritENoIn = aritE

binaryE (AEBinary o x y)  
	| showd o == "as" = do{ x' <- aritE x >>= (\c -> return $ splitLR c); y' <- aritE y >>= (\c -> return $ splitLR c); return $ "cast( "++ (x'!!1) ++", "++ (y'!!1) ++")" ++ (y'!!2) }
    | otherwise       = do{ x' <- aritE x; y' <- aritE y; return $ x' ++ showb o ++ y'}

condE (CondE e o) = do{ e' <- aritE e; o' <- maybe (return "") (\(q, e1, c, e2) -> do{ e1' <- assignE e1; e2' <- assignE e2; return $ showb q ++ e1' ++ showb c ++ e2'}) o; return $ e' ++ o'}

condENoIn = condE

nonAssignE (NAssignE e o) = do{ e' <- aritE e; o' <- maybe (return "") (\(q, e1, c, e2) -> do{ e1' <- nonAssignE e1; e2' <- nonAssignE e2; return $ showb q ++ e1' ++ showb c ++ e2'}) o; return $ e' ++ o'}

nonAssignENoIn = nonAssignE

assignE x = case x of
                ALogical p o a  -> do{ p' <- postFixE p; a' <- assignE a; return $ p' ++ showb o ++ a' } 
                ACompound p o a -> do{ p' <- postFixE p; a' <- assignE a; return $ p' ++ showb o ++ a' } 
                AAssign p o a   -> do{ p' <- postFixE p; a' <- assignE a; return $ p' ++ showb o ++ a' } 
                ACond e         -> condE e >>= return

assignENoIn = assignE

typeE = nonAssignE
typeENoIn = nonAssignENoIn

expr (Expr x) = assignE x

forS (ForS k l finit s e s1 e1 r b) = 
    do{ fheader <- maybe (return "") forInit finit
      ; ftest <-  maybe (return "") listE e
      ; ftail <- maybe (return "") listE e1
      ; fblock <- forBlock b ftail
      ; ws <- wsBlock b
      ; return $ fheader ++ ";" ++ init ws ++ "while " ++ showb l ++ ftest ++ showb r ++ fblock
      }
    where forInit i = do case i of
                             FIListE l -> listE l >>= return
                             FIVarS v  -> varS v >>= return
          forBlock (Block l bs r) tail = do{ bi <-  foldlM (\s b -> do{ x <- blockItem b; return $ s ++ x} ) "" bs 
                                           ; return $ showb l ++ bi ++ "\t" ++ tail ++ ";" ++ init (showw l) ++ showb r }
          wsBlock (Block l bs r) = return $ showw l
