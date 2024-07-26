module Elm.Parser.TypeAnnotation exposing (typeAnnotation, typeAnnotationNoFnExcludingTypedWithArguments)

import Elm.Parser.Layout as Layout
import Elm.Parser.Node as Node
import Elm.Parser.Tokens as Tokens
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (RecordDefinition, RecordField, TypeAnnotation)
import Parser as Core exposing ((|.), (|=), Parser)
import Parser.Extra
import ParserWithComments exposing (WithComments)
import Rope


typeAnnotation : Parser (WithComments (Node TypeAnnotation))
typeAnnotation =
    Core.map
        (\ta ->
            \afterTa ->
                case afterTa of
                    Nothing ->
                        ta

                    Just out ->
                        { comments = Rope.flatFromList [ ta.comments, out.comments ]
                        , syntax = Node.combine TypeAnnotation.FunctionTypeAnnotation ta.syntax out.syntax
                        }
        )
        (Core.lazy (\() -> typeAnnotationNoFnIncludingTypedWithArguments))
        |= Core.oneOf
            [ Core.map
                (\commentsBeforeArrow ->
                    \commentsAfterArrow ->
                        \typeAnnotationResult ->
                            Just
                                { comments =
                                    Rope.flatFromList
                                        [ commentsBeforeArrow
                                        , commentsAfterArrow
                                        , typeAnnotationResult.comments
                                        ]
                                , syntax = typeAnnotationResult.syntax
                                }
                )
                (Layout.maybeLayout |> Core.backtrackable)
                |. Tokens.arrowRight
                |= Layout.maybeLayout
                |= Core.lazy (\() -> typeAnnotation)
            , Core.succeed Nothing
            ]


typeAnnotationNoFnExcludingTypedWithArguments : Parser (WithComments (Node TypeAnnotation))
typeAnnotationNoFnExcludingTypedWithArguments =
    Core.oneOf
        [ parensTypeAnnotation
        , typedTypeAnnotationWithoutArguments
        , genericTypeAnnotation
        , recordTypeAnnotation
        ]
        |> Node.parser


typeAnnotationNoFnIncludingTypedWithArguments : Parser (WithComments (Node TypeAnnotation))
typeAnnotationNoFnIncludingTypedWithArguments =
    Core.oneOf
        [ parensTypeAnnotation
        , typedTypeAnnotationWithArguments
        , genericTypeAnnotation
        , recordTypeAnnotation
        ]
        |> Node.parser


parensTypeAnnotation : Parser (WithComments TypeAnnotation)
parensTypeAnnotation =
    Tokens.parensStart
        |> Parser.Extra.continueWith
            (Core.oneOf
                [ Tokens.parensEnd
                    |> Core.map (\() -> unitWithComments)
                , (Core.map
                    (\commentsBeforeFirstPart ->
                        \firstPart ->
                            \commentsAfterFirstPart ->
                                \lastToSecondPart ->
                                    { comments =
                                        Rope.flatFromList
                                            [ commentsBeforeFirstPart
                                            , firstPart.comments
                                            , commentsAfterFirstPart
                                            , lastToSecondPart.comments
                                            ]
                                    , syntax =
                                        case lastToSecondPart.syntax of
                                            [] ->
                                                let
                                                    (Node _ firstPartValue) =
                                                        firstPart.syntax
                                                in
                                                firstPartValue

                                            _ ->
                                                TypeAnnotation.Tupled (firstPart.syntax :: List.reverse lastToSecondPart.syntax)
                                    }
                    )
                    Layout.maybeLayout
                    |= typeAnnotation
                    |= Layout.maybeLayout
                    |= ParserWithComments.manyWithoutReverse
                        ((Tokens.comma
                            |> Parser.Extra.continueWith
                                (Core.map
                                    (\commentsBefore ->
                                        \typeAnnotationResult ->
                                            \commentsAfter ->
                                                { comments =
                                                    Rope.flatFromList
                                                        [ commentsBefore
                                                        , typeAnnotationResult.comments
                                                        , commentsAfter
                                                        ]
                                                , syntax = typeAnnotationResult.syntax
                                                }
                                    )
                                    Layout.maybeLayout
                                )
                         )
                            |= typeAnnotation
                            |= Layout.maybeLayout
                        )
                  )
                    |. Tokens.parensEnd
                ]
            )


unitWithComments : WithComments TypeAnnotation
unitWithComments =
    { comments = Rope.empty, syntax = TypeAnnotation.Unit }


genericTypeAnnotation : Parser (WithComments TypeAnnotation)
genericTypeAnnotation =
    Tokens.functionName
        |> Core.map (\var -> { comments = Rope.empty, syntax = TypeAnnotation.GenericType var })


recordTypeAnnotation : Parser (WithComments TypeAnnotation)
recordTypeAnnotation =
    ((Tokens.curlyStart
        |> Parser.Extra.continueWith
            (Core.map
                (\commentsBefore ->
                    \afterCurly ->
                        case afterCurly of
                            Nothing ->
                                { comments = commentsBefore
                                , syntax = TypeAnnotation.Record []
                                }

                            Just afterCurlyResult ->
                                { comments =
                                    Rope.flatFromList
                                        [ commentsBefore
                                        , afterCurlyResult.comments
                                        ]
                                , syntax = afterCurlyResult.syntax
                                }
                )
                Layout.maybeLayout
            )
     )
        |= Core.oneOf
            [ Node.parserCoreMap
                (\firstName ->
                    \commentsAfterFirstName ->
                        \afterFirstName ->
                            Just
                                { comments =
                                    Rope.flatFromList
                                        [ commentsAfterFirstName
                                        , afterFirstName.comments
                                        ]
                                , syntax =
                                    case afterFirstName.syntax of
                                        RecordExtensionExpressionAfterName fields ->
                                            TypeAnnotation.GenericRecord firstName fields

                                        FieldsAfterName fieldsAfterName ->
                                            TypeAnnotation.Record (Node.combine Tuple.pair firstName fieldsAfterName.firstFieldValue :: fieldsAfterName.tailFields)
                                }
                )
                Tokens.functionName
                |= Layout.maybeLayout
                |= Core.oneOf
                    [ Tokens.pipe
                        |> Parser.Extra.continueWith
                            (Node.parserMap
                                RecordExtensionExpressionAfterName
                                recordFieldsTypeAnnotation
                            )
                    , (Tokens.colon
                        |> Parser.Extra.continueWith
                            (Core.map
                                (\commentsBeforeFirstFieldValue ->
                                    \firstFieldValue ->
                                        \commentsAfterFirstFieldValue ->
                                            \tailFields ->
                                                { comments =
                                                    Rope.flatFromList
                                                        [ commentsBeforeFirstFieldValue
                                                        , firstFieldValue.comments
                                                        , commentsAfterFirstFieldValue
                                                        , tailFields.comments
                                                        ]
                                                , syntax =
                                                    FieldsAfterName
                                                        { firstFieldValue = firstFieldValue.syntax
                                                        , tailFields = tailFields.syntax
                                                        }
                                                }
                                )
                                Layout.maybeLayout
                            )
                      )
                        |= typeAnnotation
                        |= Layout.maybeLayout
                        |= Core.oneOf
                            [ Tokens.comma
                                |> Parser.Extra.continueWith recordFieldsTypeAnnotation
                            , Core.succeed { comments = Rope.empty, syntax = [] }
                            ]
                    ]
            , Core.succeed Nothing
            ]
    )
        |. Tokens.curlyEnd


type RecordFieldsOrExtensionAfterName
    = RecordExtensionExpressionAfterName (Node RecordDefinition)
    | FieldsAfterName { firstFieldValue : Node TypeAnnotation, tailFields : List (Node RecordField) }


recordFieldsTypeAnnotation : Parser (WithComments TypeAnnotation.RecordDefinition)
recordFieldsTypeAnnotation =
    ParserWithComments.sepBy1 ","
        (Core.map
            (\commentsBefore ->
                \fields ->
                    { comments = Rope.flatFromList [ commentsBefore, fields.comments ]
                    , syntax = fields.syntax
                    }
            )
            Layout.maybeLayout
            |= Node.parser recordFieldDefinition
        )


recordFieldDefinition : Parser (WithComments TypeAnnotation.RecordField)
recordFieldDefinition =
    Core.map
        (\commentsBeforeFunctionName ->
            \functionName ->
                \commentsAfterFunctionName ->
                    \commentsAfterColon ->
                        \value ->
                            \commentsAfterValue ->
                                { comments =
                                    Rope.flatFromList
                                        [ commentsBeforeFunctionName
                                        , commentsAfterFunctionName
                                        , commentsAfterColon
                                        , value.comments
                                        , commentsAfterValue
                                        ]
                                , syntax = ( functionName, value.syntax )
                                }
        )
        Layout.maybeLayout
        |= Node.parserCore Tokens.functionName
        |= Layout.maybeLayout
        |. Tokens.colon
        |= Layout.maybeLayout
        |= typeAnnotation
        -- This extra whitespace is just included for compatibility with earlier version
        -- TODO for v8: move to recordFieldsTypeAnnotation
        |= Layout.maybeLayout


typedTypeAnnotationWithoutArguments : Parser (WithComments TypeAnnotation)
typedTypeAnnotationWithoutArguments =
    Core.map
        (\original -> { comments = Rope.empty, syntax = TypeAnnotation.Typed original [] })
        typeIndicator


typeIndicator : Core.Parser (Node ( ModuleName, String ))
typeIndicator =
    Tokens.typeName
        |> Core.andThen (\typeOrSegment -> typeIndicatorHelper [] typeOrSegment)
        |> Node.parserCore


typeIndicatorHelper : ModuleName -> String -> Core.Parser ( ModuleName, String )
typeIndicatorHelper moduleNameSoFar typeOrSegment =
    Core.oneOf
        [ Tokens.dot
            |> Parser.Extra.continueWith Tokens.typeName
            |> Core.andThen (\t -> typeIndicatorHelper (typeOrSegment :: moduleNameSoFar) t)
        , Core.lazy (\() -> Core.succeed ( List.reverse moduleNameSoFar, typeOrSegment ))
        ]


typedTypeAnnotationWithArguments : Parser (WithComments TypeAnnotation)
typedTypeAnnotationWithArguments =
    Core.map
        (\qualified ->
            \args ->
                { comments = args.comments
                , syntax = TypeAnnotation.Typed qualified args.syntax
                }
        )
        typeIndicator
        |= ParserWithComments.many
            (Core.map
                (\commentsBefore ->
                    \typeAnnotationResult ->
                        { comments = Rope.flatFromList [ commentsBefore, typeAnnotationResult.comments ]
                        , syntax = typeAnnotationResult.syntax
                        }
                )
                (Layout.maybeLayout |> Core.backtrackable)
                |= typeAnnotationNoFnExcludingTypedWithArguments
            )
