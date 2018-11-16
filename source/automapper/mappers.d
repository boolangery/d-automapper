/**
    Mappers.
*/
module automapper.mappers;

import std.traits;
import automapper;

class Mapper(A, B) : MapperBase!(A, B) if (is(A == B))
{
    this(AutoMapper context) { super(context); }

    override B map(A value)
    {
        return value;
    }
}

/// A class mapper.
class Mapper(A, B) : MapperBase!(A, B) if (is(A == class) && is(B == class))
{
    import std.algorithm;

private:
    enum ExcludedMember = [
        "Monitor"
    ];

    string[string] _customMemberMapping;

public:
    this(AutoMapper context) { super(context); }

    override B map(A value)
    {
        // TODO: assert default constructor
        B inst = new B();

        // iterate all members of A
        static foreach(memberOfA; [__traits(allMembers, A)]) {
            // select non callable member of A and not in excluded list
            static if (!isCallable!(__traits(getMember, value, memberOfA)) && !ExcludedMember.canFind(memberOfA)) {

                // check if B has member A
                static if (__traits(hasMember, B, memberOfA)) {
                    // check same type
                    static if (typeid(__traits(getMember, value, memberOfA)) is typeid(__traits(getMember, inst, memberOfA))) {

                        pragma(msg, memberOfA);

                        __traits(getMember, inst, memberOfA) = context.map!(typeof(__traits(getMember, value, memberOfA)),
                            typeof(__traits(getMember, inst, memberOfA)))(__traits(getMember, value, memberOfA));
                    }
                }
                else if (memberOfA in _customMemberMapping) {

                }
            }
        }

        return inst;
    }



    final auto forMember(string FromMember, string ToMember)()
    {
        static assert(hasMember!(B, FromMember), FromMember ~ " is not a member of " ~ B.stringof);
        static assert(hasMember!(A, ToMember),   ToMember ~ " is not a member of " ~ A.stringof);



        _customMemberMapping[FromMember] = ToMember;

        return this;
    }

    unittest
    {
        auto mapper = new AutoMapper();
        mapper.createMap!(ClassA, ClassC).forMember!("title", "str");

        auto classC = mapper.map!(ClassA, ClassC)(new ClassA());
        import std.stdio;
        writeln(classC.title);
        writeln(classC.value);
    }
}
