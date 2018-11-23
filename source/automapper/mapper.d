/**
    Contains mapper.
*/
module automapper.mapper;

import automapper.meta;


/**
    Used to create a new mapper definition in AutoMapper.
    Template_Params:
        F = The type to map from
        T = The type to map to
        M = A list of CustomMapping (ForMember, Ignore...) or a delegate to define
            a type converter
**/
abstract class Mapper(F, T)
{
    alias A = F;
    alias B = T;

    abstract B map(A a);
}

class ClassStructMapper(A, B, Mappings...) : Mapper!(A, B)
{
    override B map(AutoMapper)(A a, AutoMapper am)
    {
        // init return value
        static if (isClass!B)
            B b = new B();
        else
            B b;

        // auto complete mappping
        alias AutoMapping = completeUserMapping!(A, B, Mappings);

        // warn about un-mapped members in B
        static foreach(member; ClassMembers!B) {
            static if (!buildMappedMemberList!(AutoMapping).canFind(member)) {
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
            static if (isCustomMemberMapping!Mapping) {
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
                        __traits(getMember, b, Mapping.MapTo) = this.map!(
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
