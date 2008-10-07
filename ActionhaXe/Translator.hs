-- Translate an Actionscript 3 AST to haXe and hxml for Flash 9

module ActionhaXe.Translator where

import ActionhaXe.Lexer
import ActionhaXe.Data
import ActionhaXe.Prim
import ActionhaXe.Parser
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Control.Monad.State
import Data.Foldable (foldlM, foldrM)
import Data.List (intercalate)

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
                             put st{initMembers = Set.insert output (initMembers st)}
                             st' <- get
                             return ()

getMembers = do st <- get
                let ret = Set.toList (initMembers st)
                put st{initMembers = Set.empty}
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
    bi <- foldlM (\s b -> do{ x <- blockItem b; return $ s ++ x} ) "" bs 
    return $ showw l ++ bi

block (Block l bs r)  = do 
    bi <-  foldlM (\s b -> do{ x <- blockItem b; return $ s ++ x} ) "" bs 
    return $ showb l ++ bi ++ showb r

constructorBlock (Block l bs r) = do 
    bi <-  foldrM (\b s -> do{ x <- blockItem b; return $ x ++ s} ) "" bs 
    --let i = (reverse $ break (\c -> c == '\n') ( reverse $ showw l)) ++ "test"
    let spacebreak = break (\c -> c == '\n') ( reverse $ showw l)
    let i =  reverse $ fst spacebreak
    let nl = if (snd spacebreak)!!1 == '\r' then "\r\n" else "\n"
    x <- getMembers
    let init = "// initialized members"++nl++i++ intercalate (nl++i) x
    return $ showb l ++ init ++ nl ++ i ++ bi ++ showb r

blockItem b = do x <- case b of  -- Use the list monad here to try all possible paths?
                        Tok t                       -> do{ x <- tok t; return x}
                        Block _ _ _                 -> do{ x <- block b; return x} 
                        ImportDecl _ _ _            -> do{ return $ importDecl b }
                        ClassDecl _ _ _ _ _ _       -> do{ x <- classDecl b; return x}
                        MethodDecl _ _ _ _ _ _      -> do{ x <- methodDecl b; return x} 
                        MemberVarDecl _ _ _ _ _ _ _ -> do{ x <- memberVarDecl b; return x}
                        VarDecl _ _ _ _ _ _         -> do{ return $ varDecl b}
                        Expr _                      -> do{ return $ expr b}
                 return x

tok t = do let x = showb t
           f <- getFlag fpackage
           return x

importDecl (ImportDecl i n s) = foldr (\t s -> showb t ++ s) "" [i,n] ++ maybeEl showb s  -- look up and adjust

classDecl (ClassDecl a c n e i b) = do
    updateFlag fclass $ showd n
    updateFlag fclassAttr $ publicAttr a
    packageName <- getFlag fpackage
    if packageName == mainPackage
         then do x <- block b
                 return $ attr a ++ showb c ++ showb n ++ maybeEl showl e ++ implements i ++ x 
         else do x <- block b
                 return $ attr a ++ showb c ++ showb n ++ maybeEl showl e ++ implements i ++ x 
    where publicAttr as = if "public" `elem` map (\a -> showd a) as then "public" else "private"
          attr as = concat $ map (\attr -> case (showd attr) of { "internal" -> "private" ++ showw attr; "public" -> ""; x -> showb attr }) as
          implements is = maybeEl showl is

methodDecl (MethodDecl a f ac n s b) = do 
    packageName <- getFlag fpackage
    className <- getFlag fclass
    classAttr <- getFlag fclassAttr
    if packageName == mainPackage && className == (showd n) && classAttr == "public"
        then do{ x <- block b; return $ "static " ++ showb f ++ "main() "++ x }
        else if className == (showd n)
                 then do{ x <- constructorBlock b; return $ attr a ++ showb f ++ "new"++showw n ++ signatureArgs s ++ x }
                 else do{ x <- block b;  return $ attr a ++ showb f ++ accessor ac ++ showb n ++ signature s ++ x }
    where attr as = concat $ map (\attr -> case (showd attr) of { "internal" -> "private" ++ showw attr; "protected" -> "public" ++ showw attr; x -> showb attr }) as
          --inMainAttr as = concat $ map (\attr -> case (showd attr) of { "internal" -> "private" ++ showw attr; "protected" -> "public" ++ showw attr; x -> showb attr }) as
          accessor ac = maybeEl showb ac
          funcname n = showb n -- if method has same name as class then replace with new

signatureArgs (Signature l args r ret) = showb l ++ showArgs args  ++ showb r

rettype ret = case ret of
                  Just (c, t) -> showb c ++ datatype t
                  Nothing     -> ""

signature (Signature l args r ret) = showb l ++ showArgs args  ++ showb r ++ rettype ret

showArgs as = concat $ map showArg as
    where showArg (Arg n c t md mc) = (case md of{ Just d  -> "?"; Nothing -> ""}) ++ showb n ++ showb c ++ datatype t ++ maybeEl showl md ++ maybeEl showb mc


memberVarDecl (MemberVarDecl ns v n c d i s) = do 
    if maybe False (\x -> elem "static" (map (\n -> showd n) x )) ns || (maybe True (const False) i)
        then return $ namespace ns ++ "var" ++ showw v ++ showl [n,c] ++ datatype d ++ maybeEl showl i ++ maybeEl showb s 
        else do insertInitMember (showb n ++ maybeEl showl i ++ ";")
                return $ namespace ns ++ "var" ++ showw v ++ showl [n,c] ++ datatype d ++ maybeEl showb s

varDecl (VarDecl ns v n c d s) = namespace ns ++ "var" ++ showw v ++ showl [n,c] ++ datatype d ++ maybeEl showb s

namespace ns = case ns of 
                   Just x -> concat $ map (\n -> (case (showd n) of { "protected" -> "public"; _ -> showd n})  ++ showw n) x
                   Nothing -> ""

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

expr (Expr x) = assignE x

assignE x = primaryE x

primaryE x = case x of
                 PEThis x -> showb x
                 PEIdent x -> showb x
                 PELit x -> showb x
                 PEArray x -> arrayLit x
                 PEObject x -> objectLit x
                 PERegex x -> "~" ++ showb x
                 PEXml x -> "Xml.parse(\""++ showd x ++ "\")" ++ showw x
                 PEParens l x r -> showb l ++ expr x ++ showb r

arrayLit (ArrayLitC l x r) = showb l ++ maybe "" elision x ++ showb r

elementList (El l e el r) = maybeEl elision l ++ assignE e ++ foldr (\(EAE c p) s -> elision c ++ assignE p ++ s) "" el ++ maybeEl elision r

elision (Elision x) = showl x

objectLit (ObjectLit l x r) = showb l ++ maybe "" propertyNameAndValueList x ++ showb r

propertyNameAndValueList (PropertyList x) = foldr (\(p, c, e, s) str -> showb p ++ showb c ++ assignE e ++ maybe "" showb s ++ str) "" x
