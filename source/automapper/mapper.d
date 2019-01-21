/*
    Contains class/struct mapper.
*/
module automapper.mapper;

import automapper.meta;
import automapper.naming;
import automapper.type.converter;
import automapper.value.transformer;
import automapper.config;


/**
    Allow to create compile-time generated class and struct mapper.
*/
package class ObjectMapper(MapperConfig) if (isObjectMapperConfig!MapperConfig)
{
    // trick to get config specialization
    static if (is(MapperConfig : ObjectMapperConfig!(TSource, TDest, TSourceConv, TDestConv, Reverse, Mappings),
        TSource, TDest, TSourceConv, TDestConv, bool Reverse, Mappings...))
    {
        alias A = TSource;
        alias B = TDest;

        static B map(AutoMapper)(A a, AutoMapper am)
        {
            import std.algorithm : canFind;

            // init return value
            static if (isClass!B)
                B b = new B();
            else
                B b;

            // auto complete mappping
            alias AutoMapping = Mappings;

            // warn about un-mapped members in B
            static foreach(member; ClassMembers!B) {
                static if (!listMappedObjectMember!(AutoMapping).canFind(member)) {
                    static assert(false, "non mapped member in destination object '" ~ B.stringof ~"." ~ member ~ "'");
                }
            }

            // instanciate class member
            static foreach(member; ClassMembers!B) {
                static if (isClass!(MemberType!(B, member))) {
                    __traits(getMember, b, member) = new MemberType!(B, member);
                }
            }

            // generate mapping code
            static foreach(Mapping; AutoMapping) {
                static if (isObjectMemberMappingConfig!Mapping) {
                    static assert(hasNestedMember!(B, Mapping.DestMember), Mapping.DestMember ~ " is not a member of " ~ 
                        B.stringof);

                    // ForMember - mapMember
                    static if (isForMember!(Mapping, ForMemberConfigType.mapMember)) {
                        static assert(hasNestedMember!(A, Mapping.Action), Mapping.Action ~ " is not a member of " ~ 
                            A.stringof);

                        // same type
                        static if (is(MemberType!(B, Mapping.DestMember) == MemberType!(A, Mapping.Action))) {
                            mixin(GetMember!(b, Mapping.DestMember)) = 
                                am.transform(mixin(GetMember!(a, Mapping.Action))); // b.member = a. member;
                        }
                        // different type: map
                        else {
                            __traits(getMember, b, Mapping.DestMember) = am.map!(
                                MemberType!(B, Mapping.DestMember),
                                MemberType!(A, Mapping.Action))(__traits(getMember, a, Mapping.Action)); // b.member = context.map(a.member);
                        }
                    }
                    // ForMember - mapDelegate
                    else static if (isForMember!(Mapping, ForMemberConfigType.mapDelegate)) {
                        // static assert return type
                        static assert(is(ReturnType!(Mapping.Action) == MemberType!(B, Mapping.DestMember)),
                            "the func in " ~ ForMember.stringof ~ " must return a '" ~
                            MemberType!(B, Mapping.DestMember).stringof ~ "' like " ~ B.stringof ~
                            "." ~ Mapping.DestMember);
                        // static assert parameters
                        static assert(Parameters!(Mapping.Action).length is 1 && is(Parameters!(Mapping.Action)[0] == A),
                            "the func in " ~ ForMember.stringof ~ " must take a value of type '" ~ A.stringof ~"'");
                        __traits(getMember, b, Mapping.DestMember) = Mapping.Action(a);
                    }
                }
            }

            return b;
        }
    }
}

package template isObjectMapper(T)
{
    enum bool isObjectMapper = (is(T: ObjectMapper!(A, B), A, B) ||
        is(T: ObjectMapper!(A, B, M), M));
}

/**
    It take a list of Mapper, and return a new list of reversed mapper if needed.
*/
package template generateReversedMapperConfig(MapperConfigs...) if (allSatisfy!(isObjectMapperConfig, MapperConfigs))
{
    import automapper.api;

    private template generateReversedMapperConfigImpl(size_t idx) {
        static if (idx < MapperConfigs.length) {
            alias Config = MapperConfigs[idx];

            private template reverseMapping(size_t midx) {
                static if (midx < Config.Mappings.length) {
                    alias MP = Config.Mappings[midx];

                    static if (isForMember!(MP, ForMemberConfigType.mapMember)) {
                        alias reverseMapping = AliasSeq!(ForMemberConfig!(MP.Action, MP.DestMember), 
                            reverseMapping!(midx + 1));
                    }
                    else static if (isForMember!(MP, ForMemberConfigType.mapDelegate)) {
                        static assert(false, "Cannot reverse mapping '" ~ Config.TSource.stringof ~ " -> " ~ 
                            Config.TDest.stringof ~ "' because it use a custom user delegate: " ~ MP.stringof);
                    }
                    else
                        alias reverseMapping = reverseMapping!(midx + 1); // continue
                }
                else
                    alias reverseMapping = AliasSeq!();
            }

            static if (Config.Reverse) // reverse it if needed
                alias generateReversedMapperConfigImpl = AliasSeq!(CreateMap!(Config.TDest, Config.TSource, 
                    reverseMapping!0),
                    generateReversedMapperConfigImpl!(idx + 1));
            else
                alias generateReversedMapperConfigImpl = generateReversedMapperConfigImpl!(idx + 1); // continue
        }
        else
            alias generateReversedMapperConfigImpl = AliasSeq!();
    }

    alias generateReversedMapperConfig = generateReversedMapperConfigImpl!0;
}

/**
    List mapped object member.
    Params:
        Mappings = a list of ObjectMemberMapping
    Returns:
        a string[] of mapped member identifer
*/
package template listMappedObjectMember(Mappings...) if (allSatisfy!(isObjectMemberMappingConfig, Mappings))
{
    import std.string : split;

    private template listMappedObjectMemberImpl(size_t idx) {
        static if (idx < Mappings.length)
            static if (isObjectMemberMappingConfig!(Mappings[idx]))
                enum string[] listMappedObjectMemberImpl = Mappings[idx].DestMember ~ 
                    Mappings[idx].DestMember.split(".") ~ listMappedObjectMemberImpl!(idx + 1);
            else
                enum string[] listMappedObjectMemberImpl = listMappedObjectMemberImpl!(idx + 1); // skip
        else
            enum string[] listMappedObjectMemberImpl = [];
    }

    enum string[] listMappedObjectMember = listMappedObjectMemberImpl!0;
}

/**
    Try to automatically map unmapper member.

    It:
        * map member with the same name
        * map flattened member to destination object
          e.g: A.foo.bar is mapped to B.fooBar

    Params:
        TSource = The type to map from
        TDest = The type to map to
        Mappings = a list of ObjectMemberMapping
    Returns:
        A list of completed ObjectMemberMapping
*/
package template tryAutoMapUnmappedMembers(TSource, TDest, SourceConv, DestConv, Mappings...) if
    (isNamingConvention!SourceConv && isNamingConvention!DestConv &&
    allSatisfy!(isObjectMemberMappingConfig, Mappings))
{
    import std.algorithm : canFind;
    import std.string : join;

    //static if (is(TConfig : ObjectMapperConfig!(TSource, TDest, TSourceConv, TDestConv, Reverse, Mappings),

    enum MappedMembers = listMappedObjectMember!(Mappings);
    enum SourceConvention = SourceConv();
    enum DestConvention = DestConv();

    private template tryAutoMapUnmappedMembersImpl(size_t idx) {
        static if (idx < FlattenedMembers!TSource.length) {
            enum M = FlattenedMembers!TSource[idx];

            // un-mapped by user
            static if (!MappedMembers.canFind(M)) {
                // TDest has this member
                // i.e: TDest.foo = TSource.foo
                static if (hasMember!(TDest, M)) {
                    alias tryAutoMapUnmappedMembersImpl = AliasSeq!(ForMemberConfig!(M, M),
                        tryAutoMapUnmappedMembersImpl!(idx+1));
                }
                // flatenning
                // TDest has a TSource member converted with DestConvention
                // i.e: TDest.fooBar = TSource.foo.bar
                else static if (hasMember!(TDest, DestConvention.convert(M))) {
                    alias tryAutoMapUnmappedMembersImpl = AliasSeq!(ForMemberConfig!(SourceConvention.convert(M), M),
                        tryAutoMapUnmappedMembersImpl!(idx+1));
                }
                // TDest with DestConvention has a TSource member converted using SourceConvention
                // i.e: TDest.foo_bar = TSource.fooBar
                else static if (hasMember!(TDest, DestConvention.convert(SourceConvention.convertBack(M)))) {
                    alias tryAutoMapUnmappedMembersImpl = AliasSeq!(
                        ForMemberConfig!(DestConvention.convert(SourceConvention.convertBack(M)), M),
                        tryAutoMapUnmappedMembersImpl!(idx+1));
                }
                else
                    alias tryAutoMapUnmappedMembersImpl = tryAutoMapUnmappedMembersImpl!(idx+1);
            }
            else
                alias tryAutoMapUnmappedMembersImpl = tryAutoMapUnmappedMembersImpl!(idx+1);
        }
        else
            alias tryAutoMapUnmappedMembersImpl = AliasSeq!();
    }

    alias tryAutoMapUnmappedMembers = AliasSeq!(tryAutoMapUnmappedMembersImpl!0, Mappings);
}
