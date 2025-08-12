// load-tests/basic-load-test.js
import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Custom metrics
let errorRate = new Rate('errors');
let responseTime = new Trend('response_time');
let requestCount = new Counter('requests');

// Test configuration
export let options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp up to 10 users
    { duration: '5m', target: 10 },   // Stay at 10 users
    { duration: '2m', target: 20 },   // Ramp up to 20 users
    { duration: '5m', target: 20 },   // Stay at 20 users
    { duration: '2m', target: 50 },   // Ramp up to 50 users
    { duration: '5m', target: 50 },   // Stay at 50 users
    { duration: '5m', target: 0 },    // Ramp down to 0 users
  ],
  thresholds: {
    'http_req_duration': ['p(95)<500'], // 95% of requests must complete below 500ms
    'http_req_failed': ['rate<0.05'],   // Error rate must be below 5%
    'errors': ['rate<0.05'],            // Custom error rate
  },
};

const BASE_URL = __ENV.BASE_URL || 'https://gitops-platform.example.com';

// Test data
const users = [
  { username: 'testuser1', email: 'test1@example.com' },
  { username: 'testuser2', email: 'test2@example.com' },
  { username: 'testuser3', email: 'test3@example.com' },
];

const products = [
  { name: 'Test Product 1', price: 29.99, category: 'electronics' },
  { name: 'Test Product 2', price: 49.99, category: 'books' },
  { name: 'Test Product 3', price: 19.99, category: 'clothing' },
];

export function setup() {
  console.log('Starting load test setup...');
  console.log(`Target URL: ${BASE_URL}`);
  
  // Health check
  let healthCheck = http.get(`${BASE_URL}/health`);
  if (healthCheck.status !== 200) {
    console.error('Health check failed, aborting test');
    return null;
  }
  
  console.log('Setup completed successfully');
  return { baseUrl: BASE_URL };
}

export default function(data) {
  let params = {
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'k6-load-test/1.0',
    },
    timeout: '30s',
  };

  group('Homepage Load Test', function() {
    let response = http.get(`${data.baseUrl}/`, params);
    
    check(response, {
      'homepage status is 200': (r) => r.status === 200,
      'homepage response time < 2s': (r) => r.timings.duration < 2000,
      'homepage contains title': (r) => r.body.includes('GitOps Platform'),
    });
    
    requestCount.add(1);
    errorRate.add(response.status !== 200);
    responseTime.add(response.timings.duration);
  });

  group('Order Creation Flow', function() {
    // First, get a product
    let productsResponse = http.get(`${data.baseUrl}/api/products`, params);
    if (productsResponse.status === 200) {
      try {
        let products = JSON.parse(productsResponse.body);
        if (products.length > 0) {
          let product = products[0];
          
          let orderData = {
            productId: product.id,
            quantity: Math.floor(Math.random() * 5) + 1,
            customerEmail: `test${Math.random().toString(36).substr(2, 9)}@example.com`,
          };
          
          let orderResponse = http.post(`${data.baseUrl}/api/orders`, 
            JSON.stringify(orderData), params);
          
          check(orderResponse, {
            'order creation status is 201': (r) => r.status === 201,
            'order creation response time < 3s': (r) => r.timings.duration < 3000,
            'order creation returns order ID': (r) => {
              try {
                let body = JSON.parse(r.body);
                return body.orderId !== undefined;
              } catch (e) {
                return false;
              }
            },
          });
          
          requestCount.add(1);
          errorRate.add(orderResponse.status !== 201);
          responseTime.add(orderResponse.timings.duration);
        }
      } catch (e) {
        console.error('Failed to parse products response:', e);
      }
    }
  });

  group('Static Assets', function() {
    let staticAssets = ['/css/main.css', '/js/app.js', '/images/logo.png'];
    let asset = staticAssets[Math.floor(Math.random() * staticAssets.length)];
    
    let response = http.get(`${data.baseUrl}${asset}`, params);
    
    check(response, {
      'static asset loads successfully': (r) => r.status === 200 || r.status === 304,
      'static asset response time < 1s': (r) => r.timings.duration < 1000,
    });
    
    requestCount.add(1);
    errorRate.add(response.status !== 200 && response.status !== 304);
    responseTime.add(response.timings.duration);
  });

  // Random sleep between 1-3 seconds to simulate user behavior
  sleep(Math.random() * 2 + 1);
}

export function teardown(data) {
  console.log('Load test completed');
  console.log(`Total requests made: ${requestCount.count}`);
  console.log(`Average response time: ${responseTime.avg}ms`);
  console.log(`Error rate: ${(errorRate.rate * 100).toFixed(2)}%`);
}

// Stress test configuration for separate runs
export let stressTestOptions = {
  stages: [
    { duration: '2m', target: 100 }, // Ramp up to 100 users
    { duration: '5m', target: 100 }, // Stay at 100 users
    { duration: '2m', target: 200 }, // Ramp up to 200 users
    { duration: '5m', target: 200 }, // Stay at 200 users
    { duration: '2m', target: 300 }, // Ramp up to 300 users
    { duration: '5m', target: 300 }, // Stay at 300 users
    { duration: '10m', target: 0 },  // Ramp down to 0 users
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000'], // Allow higher response times under stress
    'http_req_failed': ['rate<0.1'],     // Allow higher error rate under stress
  },
};

// Spike test configuration
export let spikeTestOptions = {
  stages: [
    { duration: '10s', target: 100 }, // Spike to 100 users
    { duration: '1m', target: 100 },  // Stay at 100 users
    { duration: '10s', target: 1000 }, // Spike to 1000 users
    { duration: '3m', target: 1000 },  // Stay at 1000 users
    { duration: '10s', target: 100 },  // Drop back to 100 users
    { duration: '3m', target: 100 },   // Stay at 100 users
    { duration: '10s', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<2000'], // Allow even higher response times during spikes
    'http_req_failed': ['rate<0.2'],     // Allow higher error rate during spikes
  },
};status !== 200);
    responseTime.add(response.timings.duration);
  });

  group('API Health Check', function() {
    let response = http.get(`${data.baseUrl}/api/health`, params);
    
    check(response, {
      'health check status is 200': (r) => r.status === 200,
      'health check response time < 1s': (r) => r.timings.duration < 1000,
      'health check returns JSON': (r) => r.headers['Content-Type'].includes('application/json'),
    });
    
    requestCount.add(1);
    errorRate.add(response.status !== 200);
    responseTime.add(response.timings.duration);
  });

  group('User Registration Flow', function() {
    let user = users[Math.floor(Math.random() * users.length)];
    user.username = `${user.username}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    let registrationData = {
      username: user.username,
      email: user.email,
      password: 'testpassword123',
    };
    
    let response = http.post(`${data.baseUrl}/api/users/register`, 
      JSON.stringify(registrationData), params);
    
    check(response, {
      'registration status is 201': (r) => r.status === 201,
      'registration response time < 3s': (r) => r.timings.duration < 3000,
      'registration returns user ID': (r) => {
        try {
          let body = JSON.parse(r.body);
          return body.id !== undefined;
        } catch (e) {
          return false;
        }
      },
    });
    
    requestCount.add(1);
    errorRate.add(response.status !== 201);
    responseTime.add(response.timings.duration);
  });

  group('Product Listing', function() {
    let response = http.get(`${data.baseUrl}/api/products`, params);
    
    check(response, {
      'products list status is 200': (r) => r.status === 200,
      'products list response time < 2s': (r) => r.timings.duration < 2000,
      'products list returns array': (r) => {
        try {
          let body = JSON.parse(r.body);
          return Array.isArray(body);
        } catch (e) {
          return false;
        }
      },
    });
    
    requestCount.add(1);
    errorRate.add(response.status !== 200);
    responseTime.add(response.timings.duration);
  });

  group('Product Search', function() {
    let searchTerm = ['electronics', 'books', 'clothing'][Math.floor(Math.random() * 3)];
    let response = http.get(`${data.baseUrl}/api/products/search?q=${searchTerm}`, params);
    
    check(response, {
      'search status is 200': (r) => r.status === 200,
      'search response time < 2s': (r) => r.timings.duration < 2000,
    });
    
    requestCount.add(1);
    errorRate.add(response.