module Elm.Parser.ExposeTests exposing (all)

import Elm.Parser.CombineTestUtil exposing (..)
import Elm.Parser.Expose exposing (..)
import Elm.Syntax.Exposing exposing (..)
import Elm.Syntax.Node exposing (Node(..))
import Elm.Syntax.Range exposing (..)
import Expect
import Test exposing (..)


all : Test
all =
    describe "ExposeTests"
        [ test "infixExpose" <|
            \() ->
                parseFullStringWithNullState "($>)" infixExpose
                    |> Maybe.map noRangeExpose
                    |> Expect.equal (Just (Node empty <| InfixExpose "$>"))
        , test "definitionExpose" <|
            \() ->
                parseFullStringWithNullState "Model" typeExpose
                    |> Maybe.map noRangeExpose
                    |> Expect.equal (Just (Node empty <| TypeOrAliasExpose "Model"))
        , test "typeExpose" <|
            \() ->
                parseFullStringWithNullState "Msg(..)" typeExpose
                    |> Maybe.map noRangeExpose
                    |> Expect.equal (Just (Node empty <| TypeExpose (ExposedType "Msg" (Just empty))))
        , test "exposingList" <|
            \() ->
                parseFullStringWithNullState "exposing (Model,Msg(..),Info(..),init,(::))" exposeDefinition
                    |> Maybe.map noRangeExposingList
                    |> Expect.equal
                        (Just
                            (Explicit
                                [ Node empty <| TypeOrAliasExpose "Model"
                                , Node empty <| TypeExpose (ExposedType "Msg" (Just empty))
                                , Node empty <| TypeExpose (ExposedType "Info" (Just empty))
                                , Node empty <| FunctionExpose "init"
                                , Node empty <| InfixExpose "::"
                                ]
                            )
                        )
        , test "exposingListInner with comment" <|
            \() ->
                parseFullStringWithNullState "foo\n --bar\n " exposingListInner
                    |> Maybe.map noRangeExposingList
                    |> Expect.equal
                        (Just
                            (Explicit
                                [ Node empty <| FunctionExpose "foo"
                                ]
                            )
                        )
        , test "exposingList with comment 2" <|
            \() ->
                parseFullStringWithNullState "exposing (foo\n --bar\n )" exposeDefinition
                    |> Maybe.map noRangeExposingList
                    |> Expect.equal
                        (Just
                            (Explicit
                                [ Node empty <| FunctionExpose "foo"
                                ]
                            )
                        )
        , test "exposingList with spacing" <|
            \() ->
                parseFullStringWithNullState "exposing (Model, Msg, Info   (..)   ,init,(::) )" exposeDefinition
                    |> Maybe.map noRangeExposingList
                    |> Expect.equal
                        (Just
                            (Explicit
                                [ Node empty <| TypeOrAliasExpose "Model"
                                , Node empty <| TypeOrAliasExpose "Msg"
                                , Node empty <| TypeExpose (ExposedType "Info" (Just empty))
                                , Node empty <| FunctionExpose "init"
                                , Node empty <| InfixExpose "::"
                                ]
                            )
                        )
        , describe "ranges"
            [ test "exposed item should not include trailing whitespace in range" <|
                let
                    input =
                        """exposing
    ( Link
    , init
    )"""
                in
                \() ->
                    parseFullStringWithNullState input exposeDefinition
                        |> Expect.equal
                            (Just
                                (Explicit
                                    [ Node { end = { column = 11, row = 2 }, start = { column = 7, row = 2 } }
                                        (TypeOrAliasExpose "Link")
                                    , Node { end = { column = 11, row = 3 }, start = { column = 7, row = 3 } }
                                        (FunctionExpose "init")
                                    ]
                                )
                            )
            ]
        ]
