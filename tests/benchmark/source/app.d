import std.stdio;
import automapper;
import std.datetime.stopwatch;
import std.conv;

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
    order.customer.name = "Eliott";
    order.customer.city = "Annecy";
    order.customer.email = "foo.bar@gmail.com";
    order.product = new Product();
    order.product.price = 99.9;
    order.product.name = "pokeball";
    return order;
}

OrderDTO manualMap(Order o) {
    auto m = new OrderDTO();
    string customerName  = o.customer.name;
    string customerCity  = o.customer.city;
    string customerEmail = o.customer.email;
    float productPrice   = o.product.price;
    string productName   = o.product.name;
    return m;
}

void main()
{
    alias Cfg = MapperConfiguration!(
        CreateMap!(Order, OrderDTO));
    auto am = Cfg.createMapper();

    int a;

    void autoMapper() {
        auto o = makeOrder();
        am.map!OrderDTO(o);
    }

    void manual() {
        auto o = makeOrder();
        manualMap(o);
    }

    auto r = benchmark!(autoMapper, manual)(50_000);

    writeln("CompileTime AutoMapper: ");
    writeln("AutoMapper: ", r[0]);
    writeln("Manual    : ", r[1]);

	writeln("---------------------------------------");

    auto rtAm = am.createRuntimeContext();

    void runtimeAutoMapper() {
        auto o = makeOrder();
        rtAm.map!OrderDTO(o);
    }

    auto r2 = benchmark!(runtimeAutoMapper, manual)(50_000);

    writeln("Runtime AutoMapper: ");
    writeln("Runtime AutoMapper: ", r2[0]);
    writeln("Manual    : ", r2[1]);
}
