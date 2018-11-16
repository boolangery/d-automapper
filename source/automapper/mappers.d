/**
    Mappers.
*/
module automapper.mappers;

import std.traits;
import automapper;

class Mapper(A, B) : MapperBase!(A, B) if ((is(A == B)) && !(is(A == class) && is(B == class)))
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

    alias CustomMappingOperation = void delegate(A, B);
    CustomMappingOperation[string] _memberMappers;

public:
    this(AutoMapper context)
    {
        super(context);

        // iterate all members of A
        static foreach(memberOfA; [__traits(allMembers, A)]) {
            // select non callable member of A and not in excluded list
            static if (!isCallable!(__traits(getMember, A, memberOfA)) && !ExcludedMember.canFind(memberOfA)) {
                // check if B has member A
                static if (__traits(hasMember, B, memberOfA)) {
                    // check same type
                    // static if (typeid(__traits(getMember, value, memberOfA)) is typeid(__traits(getMember, inst, memberOfA))) {
                        _memberMappers[memberOfA] = (A from, B to) {
                            __traits(getMember, to, memberOfA) = context.map!(typeof(__traits(getMember, from, memberOfA)),
                                typeof(__traits(getMember, to, memberOfA)))(__traits(getMember, from, memberOfA));
                        };
                    //}
                }
            }
        }

    }

    override B map(A value)
    {
        // TODO: assert default constructor
        B inst = new B();

        foreach(mapper; _memberMappers)
            mapper(value, inst);

        return inst;
    }


    // Tell to explicitely map a field with another.
    final auto forMember(string ToMember, string FromMember)()
    {
        static assert(hasMember!(B, ToMember),   ToMember   ~ " is not a member of " ~ B.stringof);
        static assert(hasMember!(A, FromMember), FromMember ~ " is not a member of " ~ A.stringof);

        _memberMappers[ToMember] = (A from, B to) {
            __traits(getMember, to, ToMember) = context.map!(typeof(__traits(getMember, from, FromMember)),
                typeof(__traits(getMember, to, ToMember)))(__traits(getMember, from, FromMember));
        };

        return this;
    }

    // Tell to map a field with the provided delegate.
    final auto forMember(string ToMember, T)(T delegate(A) mapper)
    {
        static assert(hasMember!(B, ToMember), ToMember ~ " is not a member of " ~ B.stringof);

        _memberMappers[ToMember] = (A from, B to) {
            static assert(is(typeof(__traits(getMember, to, ToMember)) == T),
                "incompatible types: " ~ B.stringof ~ "." ~ ToMember ~ " is a "
                ~ typeof(__traits(getMember, to, ToMember)).stringof ~ ", the delegate return type is "
                ~ T.stringof);

            __traits(getMember, to, ToMember) = mapper(from);
        };

        return this;
    }

    // Tell to ignore a field in destination object.
    final auto ignore(string ToMember)()
    {
        static assert(hasMember!(B, ToMember), ToMember ~ " is not a member of " ~ B.stringof);

        _memberMappers[ToMember] = (A from, B to) {
            // do nothing
        };

        return this;
    }
}

// nest
unittest
{
    static class Address {
        int zipcode = 74000;
    }

    static class Person {
        Address address = new Address();
    }

    static class PersonDTO {
        Address address;
    }

    static class AddressDTO {
        int zipcode;
    }

    auto mapper = new AutoMapper();
    mapper.createMap!(Person, PersonDTO);

    auto a = new Person();
    auto b = mapper.map!PersonDTO(a);

    assert(b.address.zipcode == 74000);
}

unittest
{
    static class A {
        string title = "gone";
        int ID = 4545;
        string firstName = "Eliott";
        string lastName = "Dumeix";
        string ignore = "ignore";
    }

    static class B {
        string titre;
        int id;
        string author;
        string ignore;
    }

    auto mapper = new AutoMapper();
    mapper.createMap!(A, B)
        .forMember!("titre", "title")
        .forMember!("id", "ID")
        .forMember!("author")((src) => src.firstName ~ " " ~ src.lastName)
        .ignore!"ignore";

    auto a = new A();
    auto b = mapper.map!B(a);

    assert(b.titre == a.title);
    assert(b.id == a.ID);
    assert(b.author == "Eliott Dumeix");
    assert(b.ignore == "");
}

unittest
{
    static class A {
        string s = "1";
        int i = 2;
        float f = 3.4;
    }

    static class B {
        string s;
        int i;
        float f;
    }

    auto mapper = new AutoMapper();
    mapper.createMap!(A, B);

    auto a = new A();
    auto b = mapper.map!B(a);

    assert(b.s == a.s);
    assert(b.i == a.i);
    assert(b.f == a.f);
}
