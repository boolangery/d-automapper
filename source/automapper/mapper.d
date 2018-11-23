/**
    Contains mapper.
*/
module automapper.mapper;

import automapper.meta;


/**
    Allow to create compile-time generated class and struct mapper.
*/
package class ObjectMapper(F, T, M...)
{
    alias A = F;
    alias B = T;
    alias Mappings = tryAutoMapUnmappedMembers!(A, B, M);

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
            static if (isObjectMemberMapping!Mapping) {
                static assert(hasNestedMember!(B, Mapping.MapTo), Mapping.MapTo ~ " is not a member of " ~ B.stringof);

                // ForMember - mapMember
                static if (isForMember!(Mapping, ForMemberType.mapMember)) {
                    static assert(hasNestedMember!(A, Mapping.Action), Mapping.Action ~ " is not a member of " ~ A.stringof);

                    // same type
                    static if (is(MemberType!(B, Mapping.MapTo) == MemberType!(A, Mapping.Action))) {
                        mixin(GetMember!(b, Mapping.MapTo)) = mixin(GetMember!(a, Mapping.Action)); // b.member = a. member;
                    }
                    // different type: map
                    else {
                        __traits(getMember, b, Mapping.MapTo) = am.map!(
                            MemberType!(B, Mapping.MapTo),
                            MemberType!(A, Mapping.Action))(__traits(getMember, a, Mapping.Action)); // b.member = context.map(a.member);
                    }
                }
                // ForMember - mapDelegate
                else static if (isForMember!(Mapping, ForMemberType.mapDelegate)) {
                    // static assert return type
                    static assert(is(ReturnType!(Mapping.Action) == MemberType!(B, Mapping.MapTo)),
                        "the func in " ~ ForMember.stringof ~ " must return a '" ~
                        MemberType!(B, Mapping.MapTo).stringof ~ "' like " ~ B.stringof ~
                        "." ~ Mapping.MapTo);
                    // static assert parameters
                    static assert(Parameters!(Mapping.Action).length is 1 && is(Parameters!(Mapping.Action)[0] == A),
                        "the func in " ~ ForMember.stringof ~ " must take a value of type '" ~ A.stringof ~"'");
                    __traits(getMember, b, Mapping.MapTo) = Mapping.Action(a);
                }
            }
        }

        return b;
    }
}

package template isObjectMapper(T)
{
    enum bool isObjectMapper = (is(T: ObjectMapper!(A, B), A, B) || is(T: ObjectMapper!(AB, BB, M), AB, BB, M));
}

/**
    Base class for custom member mapping.
    Template_Params:
        MT = The member to map in the destination object
**/
package class ObjectMemberMapping(string T)
{
    enum string MapTo = T;
}

package template isObjectMemberMapping(T)
{
    enum bool isObjectMemberMapping = (is(T: ObjectMemberMapping!BM, string BM));
}

/// ForMember mapping type
package enum ForMemberType
{
    mapMember,  // map a member to another member
    mapDelegate // map a member to a delegate
}

/**
    Used to specialized a member mapping.
    Template_Params:
        T = The member name in the destination object
        F = The member name in the source object or a custom delegate
**/
class ForMember(string T, alias F) : ObjectMemberMapping!(T)
{
    static assert(is(typeof(F) == string) || isCallable!F, ForMember.stringof ~
        " Action must be a string to map a member to another member or a delegate.");

    static if (is(typeof(F) == string))
        private enum ForMemberType Type = ForMemberType.mapMember;
    else
        private enum ForMemberType Type = ForMemberType.mapDelegate;

    alias Action = F;
}

///
unittest
{
    import automapper;

    class A {
        string foo;
        int bar;
    }

    class B {
        string qux;
        int baz;
        long ts;
    }

   auto am = new AutoMapper!(
        CreateMap!(A, B,
            ForMember!("qux", "foo"),
            ForMember!("baz", "foo"),
            ForMember!("ts", (A a) => 123456 )));
}


package template isForMember(T, ForMemberType Type)
{
    static if (is(T == ForMember!(MapTo, Action), string MapTo, alias Action))
        static if (T.Type == Type)
            enum bool isForMember = true;
        else
            enum bool isForMember = false;
    else
        enum bool isForMember = false;
}

/**
    Used to ignore a member in the destination object.
    Template_Params:
        T = The member name in the destination object
**/
class Ignore(string T) : ObjectMemberMapping!(T)
{
    // do nothing
}

///
unittest
{
    import automapper;

    class A {
        string foo;
        int bar;
    }

    class B {
        string qux;
        int baz;
        long ts;
    }

   auto am = new AutoMapper!(
        CreateMap!(A, B,
            ForMember!("qux", "foo"),
            ForMember!("baz", "foo"),
            Ignore!("ts")));
}



/**
    List mapped object member.
    Params:
        Mappings = a list of ObjectMemberMapping
    Returns:
        a string[] of mapped member identifer
*/
package template listMappedObjectMember(Mappings...) if (allSatisfy!(isObjectMemberMapping, Mappings))
{
    import std.string : split;

    private template listMappedObjectMemberImpl(size_t idx) {
        static if (idx < Mappings.length)
            static if (isObjectMemberMapping!(Mappings[idx]))
                enum string[] listMappedObjectMemberImpl = Mappings[idx].MapTo ~ Mappings[idx].MapTo.split(".") ~ listMappedObjectMemberImpl!(idx + 1);
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
        A = The type to map from
        B = The type to map to
        Mappings = a list of ObjectMemberMapping
    Returns:
        A list of completed ObjectMemberMapping
*/
package template tryAutoMapUnmappedMembers(A, B, Mappings...) if (allSatisfy!(isObjectMemberMapping, Mappings))
{
    import std.algorithm : canFind;
    import std.string : join;

    enum MappedMembers = listMappedObjectMember!(Mappings);

    private template tryAutoMapUnmappedMembersImpl(size_t idx) {
        static if (idx < FlattenedMembers!A.length) {
            enum M = FlattenedMembers!A[idx];

            // un-mapped by user
            static if (!MappedMembers.canFind(M)) {
                // B has this member: B.foo = A.foo
                static if (hasMember!(B, M)) {
                    alias tryAutoMapUnmappedMembersImpl = AliasSeq!(ForMember!(M, M),
                        tryAutoMapUnmappedMembersImpl!(idx+1));
                }
                // B has this flatenned class member: B.fooBar = A.foo.bar
                else static if (hasMember!(B, M.flattenedToCamelCase())) {
                    alias tryAutoMapUnmappedMembersImpl = AliasSeq!(ForMember!(M.flattenedToCamelCase, M),
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
