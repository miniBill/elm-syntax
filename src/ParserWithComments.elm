module ParserWithComments exposing
    ( Comments
    , WithComments
    , many
    , manyWithoutReverse
    , sepBy
    , sepBy1
    )

import Elm.Syntax.Node exposing (Node)
import Parser exposing ((|=), Parser)
import Parser.Extra
import Rope exposing (Rope)


type alias WithComments res =
    { comments : Comments, syntax : res }


type alias Comments =
    Rope (Node String)


many : Parser (WithComments a) -> Parser (WithComments (List a))
many p =
    let
        manyWithoutReverseStep :
            ( Comments, List a )
            ->
                Parser.Parser
                    (Parser.Step
                        ( Comments, List a )
                        (WithComments (List a))
                    )
        manyWithoutReverseStep ( commentsSoFar, items ) =
            Parser.oneOf
                [ p
                    |> Parser.map
                        (\pResult ->
                            Parser.Loop
                                ( commentsSoFar |> Rope.prependTo pResult.comments
                                , pResult.syntax :: items
                                )
                        )
                , Parser.lazy
                    (\() ->
                        Parser.succeed
                            (Parser.Done
                                { comments = commentsSoFar
                                , syntax = List.reverse items
                                }
                            )
                    )
                ]
    in
    Parser.loop ( Rope.empty, [] ) manyWithoutReverseStep


{-| Same as [`many`](#many), except that it doesn't reverse the list.
This can be useful if you need to access the range of the last item.

Mind you the comments will be reversed either way

-}
manyWithoutReverse : Parser (WithComments a) -> Parser (WithComments (List a))
manyWithoutReverse p =
    let
        manyWithoutReverseStep :
            ( Comments, List a )
            ->
                Parser.Parser
                    (Parser.Step
                        ( Comments, List a )
                        (WithComments (List a))
                    )
        manyWithoutReverseStep ( commentsSoFar, items ) =
            Parser.oneOf
                [ p
                    |> Parser.map
                        (\pResult ->
                            Parser.Loop
                                ( commentsSoFar |> Rope.prependTo pResult.comments
                                , pResult.syntax :: items
                                )
                        )
                , Parser.lazy
                    (\() ->
                        Parser.succeed
                            (Parser.Done
                                { comments = commentsSoFar
                                , syntax = items
                                }
                            )
                    )
                ]
    in
    Parser.loop ( Rope.empty, [] ) manyWithoutReverseStep


sepBy : String -> Parser (WithComments a) -> Parser (WithComments (List a))
sepBy sep p =
    Parser.oneOf
        [ Parser.map
            (\head ->
                \tail ->
                    { comments = head.comments |> Rope.prependTo tail.comments
                    , syntax = head.syntax :: tail.syntax
                    }
            )
            p
            |= many (Parser.symbol sep |> Parser.Extra.continueWith p)
        , Parser.succeed { comments = Rope.empty, syntax = [] }
        ]


sepBy1 : String -> Parser (WithComments a) -> Parser (WithComments (List a))
sepBy1 sep p =
    Parser.map
        (\head ->
            \tail ->
                { comments = head.comments |> Rope.prependTo tail.comments
                , syntax = head.syntax :: tail.syntax
                }
        )
        p
        |= many (Parser.symbol sep |> Parser.Extra.continueWith p)
