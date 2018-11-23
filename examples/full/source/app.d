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

	writeln("Success");
}
