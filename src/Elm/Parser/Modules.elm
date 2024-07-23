module Elm.Parser.Modules exposing (moduleDefinition)

import Combine exposing (Parser)
import Elm.Parser.Base exposing (moduleName)
import Elm.Parser.Expose exposing (exposeDefinition)
import Elm.Parser.Layout as Layout
import Elm.Parser.Node as Node
import Elm.Parser.State exposing (State)
import Elm.Parser.Tokens as Tokens
import Elm.Syntax.Exposing exposing (Exposing)
import Elm.Syntax.Module exposing (DefaultModuleData, Module(..))
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node exposing (Node)
import List.Extra
import Parser as Core


moduleDefinition : Parser State Module
moduleDefinition =
    Combine.oneOf
        [ normalModuleDefinition
        , portModuleDefinition
        , effectModuleDefinition
        ]


effectWhereClause : Parser State ( String, Node String )
effectWhereClause =
    Core.map (\fnName -> \typeName_ -> ( fnName, typeName_ ))
        Tokens.functionName
        |> Combine.fromCoreIgnore (Combine.maybeIgnore Layout.layout)
        |> Combine.ignoreEntirely Tokens.equal
        |> Combine.ignore (Combine.maybeIgnore Layout.layout)
        |> Combine.keepFromCore (Node.parserCore Tokens.typeName)


whereBlock : Parser State { command : Maybe (Node String), subscription : Maybe (Node String) }
whereBlock =
    Combine.between
        Tokens.curlyStart
        Tokens.curlyEnd
        (Combine.sepBy1 ","
            (Layout.maybeAroundBothSides effectWhereClause)
        )
        |> Combine.map
            (\pairs ->
                { command = pairs |> List.Extra.find (\( fnName, _ ) -> fnName == "command") |> Maybe.map Tuple.second
                , subscription = pairs |> List.Extra.find (\( fnName, _ ) -> fnName == "subscription") |> Maybe.map Tuple.second
                }
            )


effectWhereClauses : Parser State { command : Maybe (Node String), subscription : Maybe (Node String) }
effectWhereClauses =
    Tokens.whereToken
        |> Combine.fromCoreIgnore Layout.layout
        |> Combine.continueWith whereBlock


effectModuleDefinition : Parser State Module
effectModuleDefinition =
    let
        createEffectModule : Node ModuleName -> { command : Maybe (Node String), subscription : Maybe (Node String) } -> Node Exposing -> Module
        createEffectModule name whereClauses exp =
            EffectModule
                { moduleName = name
                , exposingList = exp
                , command = whereClauses.command
                , subscription = whereClauses.subscription
                }
    in
    Core.map (\() -> \name -> \whereClauses -> \exp -> createEffectModule name whereClauses exp)
        (Core.symbol "effect")
        |> Combine.fromCoreIgnore Layout.layout
        |> Combine.ignoreEntirely Tokens.moduleToken
        |> Combine.ignore Layout.layout
        |> Combine.keepFromCore moduleName
        |> Combine.ignore Layout.layout
        |> Combine.keep effectWhereClauses
        |> Combine.ignore Layout.layout
        |> Combine.keep (Node.parser exposeDefinition)


normalModuleDefinition : Parser State Module
normalModuleDefinition =
    Core.map
        (\() ->
            \moduleName ->
                \exposingList ->
                    NormalModule (DefaultModuleData moduleName exposingList)
        )
        Tokens.moduleToken
        |> Combine.fromCoreIgnore Layout.layout
        |> Combine.keepFromCore moduleName
        |> Combine.ignore Layout.layout
        |> Combine.keep (Node.parser exposeDefinition)


portModuleDefinition : Parser State Module
portModuleDefinition =
    Core.map (\() -> \moduleName -> \exposingList -> PortModule (DefaultModuleData moduleName exposingList))
        Tokens.portToken
        |> Combine.fromCoreIgnore Layout.layout
        |> Combine.ignoreEntirely Tokens.moduleToken
        |> Combine.ignore Layout.layout
        |> Combine.keepFromCore moduleName
        |> Combine.ignore Layout.layout
        |> Combine.keep (Node.parser exposeDefinition)
