## AutoMapper
[AutoMapper](https://github.com/boolangery/d-automapper) is an object-object mapper for D like C# AutoMapper.

It use compile-time generated mapper to try to avoid any overhead.

You can run the benchmark located in `tests/benchmark`:

```bash
$ cd tests/benchmark
$ dub test
```

## Build documentation

This project is well documented:

```bash
$ dub build --build=ddox
```

## Full exemple
```D
import std.stdio;
import automapper;

class Order
{
    Customer customer;
    Product product;
}

class Product
{
    float price;
    string name;
}

class Customer
{
    string name;
    string city;
    string email;
}

class OrderDTO
{
    string customerName;
    string customerCity;
    string customerEmail;
    float productPrice;
    string productName;
}

auto makeOrder()
{
    auto order = new Order();
    order.customer = new Customer();
    order.customer.name = "boolangery";
    order.customer.city = "Annecy";
    order.customer.email = "foo.bar@gmail.com";
    order.product = new Product();
    order.product.price = 42;
    order.product.name = "universe";
    return order;
}


void main()
{
    // create a compile-time generated mapper to map from Order to OrderDTO,
    // and from OrderDTO to Order.
    auto mapper = MapperConfiguration!(
        CreateMap!(Order, OrderDTO)
            .ReverseMap!())
            .createMapper();

    auto initial = makeOrder();
    auto dto     = mapper.map!OrderDTO(initial); // map Order to OrderDTO
    auto order   = mapper.map!Order(dto); // map back OrderDTO to Order

    assert(order.customer.name  == initial.customer.name);
    assert(order.customer.city  == initial.customer.city);
    assert(order.customer.email == initial.customer.email);
    assert(order.product.price  == initial.product.price);
    assert(order.product.name   == initial.product.name);
}
```

## Custom member mapping

```D
import automapper;
import std.datetime;

class A {
    long timestamp;
}

class B {
    SysTime timestamp;
}

auto am = MapperConfiguration!(
    CreateMap!(long, SysTime)
        .ConvertUsing!((long ts) => SysTime(ts)),
    CreateMap!(A, B))
        .createMapper();
```
